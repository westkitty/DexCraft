import Foundation

struct HeuristicOptimizationResult {
    let optimizedText: String
    let selectedCandidateTitle: String
    let score: Int
    let breakdown: [String: Int]
    let warnings: [String]
}

enum HeuristicPromptOptimizer {
    private struct Candidate {
        let title: String
        let text: String
    }

    private enum SectionKey: Int, CaseIterable {
        case goal
        case context
        case constraints
        case deliverables
        case outputFormat
        case questions
        case successCriteria

        var headingTitle: String {
            switch self {
            case .goal:
                return "Goal"
            case .context:
                return "Context"
            case .constraints:
                return "Constraints"
            case .deliverables:
                return "Deliverables"
            case .outputFormat:
                return "Output Format"
            case .questions:
                return "Questions"
            case .successCriteria:
                return "Success Criteria"
            }
        }
    }

    private struct HeadingBlock {
        let title: String
        let key: SectionKey?
        var body: [String]
    }

    private struct ScoreResult {
        let score: Int
        let breakdown: [String: Int]
        let warnings: [String]
    }

    static func optimize(_ baselinePrompt: String) -> HeuristicOptimizationResult {
        let baseline = baselinePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = baseline.isEmpty ? baselinePrompt : baseline
        let originalFenceCount = PromptTextGuards.splitByCodeFences(input).reduce(into: 0) { result, segment in
            if case .codeFence = segment { result += 1 }
        }

        let baselineAnalysis = PromptHeuristics.analyze(input, originalCodeFenceBlocks: originalFenceCount)

        var candidates: [Candidate] = []
        candidates.append(Candidate(title: "0 Baseline", text: input))
        candidates.append(Candidate(title: "1 Canonicalize headings/order", text: canonicalizeCandidate(input)))
        candidates.append(Candidate(title: "2 Strengthen deliverables", text: deliverablesCandidate(input)))
        candidates.append(Candidate(title: "3 Add output format", text: outputFormatCandidate(input)))
        candidates.append(Candidate(title: "4 Add success criteria", text: successCriteriaCandidate(input)))
        candidates.append(Candidate(title: "5 Add scope bounds", text: scopeBoundsCandidate(input)))
        candidates.append(Candidate(title: "6 Add questions", text: questionsCandidate(input)))
        candidates.append(Candidate(title: "7 De-hedge language", text: deHedgedCandidate(input)))
        candidates.append(Candidate(title: "8 Dedupe/normalize whitespace", text: dedupeCandidate(input)))

        let comboDeliverablesOutput = outputFormatCandidate(deliverablesCandidate(input))
        let comboOutputSuccess = successCriteriaCandidate(outputFormatCandidate(input))
        let comboScopeQuestions = questionsCandidate(scopeBoundsCandidate(input))
        let comboDeliverablesOutputSuccess = successCriteriaCandidate(outputFormatCandidate(deliverablesCandidate(input)))
        let comboDeliverablesOutputSuccessQuestions = questionsCandidate(comboDeliverablesOutputSuccess)

        let optionalCombos: [Candidate] = [
            Candidate(title: "Combo Deliverables+Output", text: comboDeliverablesOutput),
            Candidate(title: "Combo Output+Success", text: comboOutputSuccess),
            Candidate(title: "Combo Scope+Questions", text: comboScopeQuestions),
            Candidate(title: "Combo Deliverables+Output+Success", text: comboDeliverablesOutputSuccess),
            Candidate(title: "Combo Deliverables+Output+Success+Questions", text: comboDeliverablesOutputSuccessQuestions)
        ]

        for candidate in optionalCombos {
            guard candidates.count < 16 else { break }
            candidates.append(candidate)
        }

        var scored: [(candidate: Candidate, score: ScoreResult, analysis: PromptAnalysis)] = []
        scored.reserveCapacity(candidates.count)

        for candidate in candidates {
            let analysis = PromptHeuristics.analyze(candidate.text, originalCodeFenceBlocks: originalFenceCount)
            let score = scoreCandidate(analysis: analysis)
            scored.append((candidate, score, analysis))
        }

        guard let baselineScored = scored.first else {
            return HeuristicOptimizationResult(
                optimizedText: input,
                selectedCandidateTitle: "0 Baseline",
                score: 0,
                breakdown: [:],
                warnings: []
            )
        }

        var bestIndex = 0
        for index in scored.indices {
            if scored[index].score.score > scored[bestIndex].score.score {
                bestIndex = index
            }
        }

        var selected = scored[bestIndex]
        var warnings = selected.score.warnings

        if selected.score.score <= baselineScored.score.score + 2 {
            if bestIndex != 0 {
                warnings.append(
                    "Anti-regression fallback: baseline retained (best=\(selected.score.score), baseline=\(baselineScored.score.score))."
                )
            }
            selected = baselineScored
        }

        if baselineAnalysis.scopeLeak && !selected.analysis.hasScopeBounds {
            warnings.append("Scope leak terms remain; consider tightening bounds explicitly.")
        }

        return HeuristicOptimizationResult(
            optimizedText: selected.candidate.text,
            selectedCandidateTitle: selected.candidate.title,
            score: selected.score.score,
            breakdown: selected.score.breakdown,
            warnings: warnings
        )
    }

    private static func scoreCandidate(analysis: PromptAnalysis) -> ScoreResult {
        var score = 0
        var breakdown: [String: Int] = [:]
        var warnings: [String] = []

        if analysis.hasOutputFormatHeading || analysis.hasOutputTemplate {
            score += 20
            breakdown["output_format"] = 20
        } else {
            score -= 10
            breakdown["missing_output_format"] = -10
        }

        if analysis.hasEnumeratedDeliverables {
            score += 15
            breakdown["enumerated_deliverables"] = 15
        } else {
            score -= 10
            breakdown["missing_deliverables"] = -10
        }

        if analysis.hasConstraintsHeading && analysis.hasStrongConstraintMarkers {
            score += 10
            breakdown["strong_constraints"] = 10
        }

        let ambiguityHigh = analysis.ambiguityCount >= 2 || analysis.isVagueGoal

        if ambiguityHigh && analysis.hasSuccessCriteriaHeading {
            score += 10
            breakdown["success_criteria_for_ambiguity"] = 10
        }

        if analysis.scopeLeak && analysis.hasScopeBounds {
            score += 8
            breakdown["scope_bounded"] = 8
        }

        if ambiguityHigh && analysis.hasQuestionsHeading {
            score += 5
            breakdown["questions_for_ambiguity"] = 5
        }

        let exampleBonus = min(10, analysis.examplesCount * 5)
        if exampleBonus > 0 {
            score += exampleBonus
            breakdown["examples"] = exampleBonus
        }

        if analysis.tokenEstimate > 900 {
            let scaledPenalty = -8 - min(12, ((analysis.tokenEstimate - 900) / 300) * 2)
            score += scaledPenalty
            breakdown["token_penalty"] = scaledPenalty
            warnings.append("Token estimate is high: \(analysis.tokenEstimate).")
        }

        if !analysis.contradictions.isEmpty {
            score -= 8
            breakdown["contradictions"] = -8
            warnings.append(contentsOf: analysis.contradictions)
        }

        if PromptHeuristics.usesCurlyVariablePlaceholders && analysis.unresolvedPlaceholderCount > 0 {
            score -= 6
            breakdown["unresolved_placeholders"] = -6
            warnings.append("Unresolved placeholders detected: \(analysis.unresolvedPlaceholderCount).")
        }

        return ScoreResult(score: score, breakdown: breakdown, warnings: warnings)
    }

    private static func canonicalizeCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            canonicalizeSections(in: text)
        }
    }

    private static func deliverablesCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            guard !analysis.hasEnumeratedDeliverables else { return text }
            return appendSection(
                to: text,
                title: "Deliverables",
                body: [
                    "1. Provide the primary output artifact.",
                    "2. Include implementation or action steps in deterministic order.",
                    "3. Include validation evidence for each major requirement."
                ]
            )
        }
    }

    private static func outputFormatCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            guard !(analysis.hasOutputFormatHeading || analysis.hasOutputTemplate) else { return text }

            return appendSection(
                to: text,
                title: "Output Format",
                body: [
                    "Use this markdown template exactly:",
                    "1. Summary: <one paragraph>",
                    "2. Deliverables:",
                    "   - <item 1>",
                    "   - <item 2>",
                    "3. Validation:",
                    "   - <check 1>",
                    "   - <check 2>"
                ]
            )
        }
    }

    private static func successCriteriaCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            let needsCriteria = (analysis.ambiguityCount > 0 || analysis.isVagueGoal) && !analysis.hasSuccessCriteriaHeading
            guard needsCriteria else { return text }

            return appendSection(
                to: text,
                title: "Success Criteria",
                body: [
                    "- Every requested section is present and complete.",
                    "- Instructions are specific, testable, and unambiguous.",
                    "- Output follows the required structure exactly."
                ]
            )
        }
    }

    private static func scopeBoundsCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            guard analysis.scopeLeak && !analysis.hasScopeBounds else { return text }

            return appendSection(
                to: text,
                title: "Constraints",
                body: [
                    "- Limit work to the explicit request only.",
                    "- Do not expand scope to unrelated systems or files.",
                    "- Avoid optional extras unless explicitly requested."
                ]
            )
        }
    }

    private static func questionsCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let analysis = PromptHeuristics.analyze(text, originalCodeFenceBlocks: 0)
            let ambiguityHigh = analysis.ambiguityCount >= 2 || analysis.isVagueGoal
            guard ambiguityHigh && !analysis.hasQuestionsHeading else { return text }

            return appendSection(
                to: text,
                title: "Questions",
                body: [
                    "- What is the exact target output and intended audience?",
                    "- What constraints (time, tools, style, depth) are mandatory?",
                    "- What should be considered out of scope?"
                ]
            )
        }
    }

    private static func deHedgedCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let shielded = PromptHeuristics.shieldProtectedLiterals(in: text)
            var edited = shielded.shielded

            let replacements: [(pattern: String, replacement: String)] = [
                (#"\bcould you\b"#, ""),
                (#"\btry to\b"#, ""),
                (#"\bif possible\b"#, ""),
                (#"\bideally\b"#, ""),
                (#"\bmaybe\b"#, ""),
                (#"\bmight\b"#, "must"),
                (#"\bas needed\b"#, "when required")
            ]

            for replacement in replacements {
                edited = replacingRegex(
                    replacement.pattern,
                    in: edited,
                    with: replacement.replacement,
                    options: [.caseInsensitive]
                )
            }

            let normalizedLines = edited.components(separatedBy: .newlines).map { line in
                let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
                let content = String(line.dropFirst(leadingWhitespace.count))
                    .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
                return String(leadingWhitespace) + content
            }

            let normalized = normalizedLines.joined(separator: "\n")
            return PromptHeuristics.restoreProtectedLiterals(in: normalized, table: shielded.table)
        }
    }

    private static func dedupeCandidate(_ input: String) -> String {
        transformPreservingCodeFences(input) { text in
            let lines = text.components(separatedBy: .newlines)
            var seen = Set<String>()
            var output: [String] = []
            var previousWasBlank = false

            for line in lines {
                let trimmedTrailing = line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
                let stripped = trimmedTrailing.trimmingCharacters(in: .whitespacesAndNewlines)

                if stripped.isEmpty {
                    if !previousWasBlank {
                        output.append("")
                    }
                    previousWasBlank = true
                    continue
                }

                previousWasBlank = false
                let normalized = stripped.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                if seen.insert(normalized).inserted {
                    output.append(trimmedTrailing)
                }
            }

            return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func transformPreservingCodeFences(_ input: String, transform: (String) -> String) -> String {
        let segments = PromptTextGuards.splitByCodeFences(input)
        var merged = ""
        var replacements: [String: String] = [:]
        var fenceIndex = 0

        for segment in segments {
            switch segment {
            case .text(let text):
                merged.append(text)
            case .codeFence(let fence):
                let token = "__DEXCRAFT_CODE_FENCE_\(fenceIndex)__"
                replacements[token] = fence
                merged.append(token)
                fenceIndex += 1
            }
        }

        var transformed = transform(merged)
        for (token, fence) in replacements {
            transformed = transformed.replacingOccurrences(of: token, with: fence)
        }

        return transformed
    }

    private static func canonicalizeSections(in text: String) -> String {
        let parsed = parseBlocks(from: text)
        var known: [SectionKey: [String]] = [:]
        var unknown: [HeadingBlock] = []

        for block in parsed.blocks {
            if let key = block.key {
                known[key, default: []].append(contentsOf: block.body)
            } else {
                unknown.append(block)
            }
        }

        let preambleContent = parsed.preamble
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !preambleContent.isEmpty {
            if known[.goal, default: []].isEmpty {
                known[.goal] = [preambleContent]
            } else if known[.context, default: []].isEmpty {
                known[.context] = [preambleContent]
            } else {
                unknown.insert(
                    HeadingBlock(title: "Context", key: nil, body: [preambleContent]),
                    at: 0
                )
            }
        }

        var rendered: [String] = []

        for key in SectionKey.allCases {
            let bodyLines = cleanBodyLines(known[key] ?? [])
            guard !bodyLines.isEmpty else { continue }
            rendered.append(renderSection(title: key.headingTitle, body: bodyLines))
        }

        for block in unknown {
            let bodyLines = cleanBodyLines(block.body)
            guard !bodyLines.isEmpty else { continue }
            rendered.append(renderSection(title: block.title, body: bodyLines))
        }

        let candidate = rendered.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? text : candidate
    }

    private static func appendSection(to text: String, title: String, body: [String]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = renderSection(title: title, body: body)
        if trimmed.isEmpty {
            return section
        }
        return trimmed + "\n\n" + section
    }

    private static func renderSection(title: String, body: [String]) -> String {
        "### \(title)\n" + body.joined(separator: "\n")
    }

    private static func cleanBodyLines(_ body: [String]) -> [String] {
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return text.components(separatedBy: .newlines)
    }

    private static func parseBlocks(from text: String) -> (preamble: [String], blocks: [HeadingBlock]) {
        let lines = text.components(separatedBy: .newlines)
        var preamble: [String] = []
        var blocks: [HeadingBlock] = []
        var currentHeading: HeadingBlock?

        func flushCurrent() {
            guard let currentHeading else { return }
            blocks.append(currentHeading)
        }

        for line in lines {
            if let heading = parseHeading(line) {
                flushCurrent()
                currentHeading = HeadingBlock(title: heading.title, key: heading.key, body: [])
                if !heading.inlineValue.isEmpty {
                    currentHeading?.body.append(heading.inlineValue)
                }
                continue
            }

            if currentHeading != nil {
                currentHeading?.body.append(line)
            } else {
                preamble.append(line)
            }
        }

        flushCurrent()
        return (preamble, blocks)
    }

    private static func parseHeading(_ line: String) -> (title: String, key: SectionKey?, inlineValue: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutHashes = trimmed.replacingOccurrences(
            of: #"^#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )

        let mapping: [(aliases: [String], key: SectionKey)] = [
            (["goal", "objective", "task"], .goal),
            (["context"], .context),
            (["constraints", "constraint"], .constraints),
            (["deliverables", "deliverable"], .deliverables),
            (["output format", "output contract", "format"], .outputFormat),
            (["questions", "clarifying questions"], .questions),
            (["success criteria", "acceptance criteria"], .successCriteria)
        ]

        let normalized = withoutHashes.lowercased()
        for item in mapping {
            for alias in item.aliases {
                if normalized == alias {
                    return (item.key.headingTitle, item.key, "")
                }

                let prefix = "\(alias):"
                if normalized.hasPrefix(prefix) {
                    let inlineStart = withoutHashes.index(withoutHashes.startIndex, offsetBy: prefix.count)
                    let inlineValue = withoutHashes[inlineStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return (item.key.headingTitle, item.key, inlineValue)
                }
            }
        }

        if trimmed.hasPrefix("#") {
            return (withoutHashes, nil, "")
        }

        return nil
    }

    private static func replacingRegex(
        _ pattern: String,
        in text: String,
        with template: String,
        options: NSRegularExpression.Options
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
