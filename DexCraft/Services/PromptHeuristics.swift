import Foundation

struct PromptAnalysis {
    let goalLine: String
    let ambiguityCount: Int
    let scopeLeak: Bool
    let hasDeliverablesHeading: Bool
    let hasOutputFormatHeading: Bool
    let hasConstraintsHeading: Bool
    let hasQuestionsHeading: Bool
    let hasSuccessCriteriaHeading: Bool
    let hasEnumeratedDeliverables: Bool
    let examplesCount: Int
    let contradictions: [String]
    let tokenEstimate: Int
    let hasStrongConstraintMarkers: Bool
    let hasOutputTemplate: Bool
    let hasScopeBounds: Bool
    let unresolvedPlaceholderCount: Int
    let isVagueGoal: Bool
}

enum PromptHeuristics {
    private enum RegexBank {
        static let shieldedLiteral = try! NSRegularExpression(
            pattern: #"https?://[^\s\]\)]+|\{[a-zA-Z0-9_\-]+\}|/(?:[a-zA-Z0-9._\-]+/)*[a-zA-Z0-9._\-]+(?:\.[a-zA-Z0-9._\-]+)?"#,
            options: [.caseInsensitive]
        )
        static let headingPrefix = try! NSRegularExpression(pattern: #"^#{1,6}\s*"#, options: [])
    }

    private static let regexCacheLock = NSLock()
    private static var regexCache: [String: NSRegularExpression] = [:]

    static let ambiguityTokens: [String] = [
        "improve", "optimize", "enhance", "better", "good", "nice", "robust", "clean", "simple", "easy", "fast", "best", "efficient",
        "some", "various", "etc", "and so on", "as needed", "if possible", "ideally", "maybe", "try to", "could you", "might"
    ]

    static let scopeLeakTokens: [String] = [
        "everything", "entire", "all of", "full scope", "in its entirety", "complete", "any and all"
    ]

    static let constraintMarkers: [String] = [
        "must", "must not", "never", "only", "avoid", "require", "do not", "always", "exactly", "at least", "no more than"
    ]

    static let deliverableMarkers: [String] = [
        "deliverable", "deliverables", "output", "return", "produce", "generate", "format", "structure", "schema", "template", "sections"
    ]

    static let formatMarkers: [String] = [
        "json", "yaml", "markdown", "csv", "xml", "table", "bullets", "code block", "schema", "template", "output format"
    ]

    static let usesCurlyVariablePlaceholders = true

    static func analyze(_ text: String, originalCodeFenceBlocks: Int) -> PromptAnalysis {
        let segments = PromptTextGuards.splitByCodeFences(text)
        let nonCodeText = segments.compactMap { segment -> String? in
            if case let .text(value) = segment { return value }
            return nil
        }
        .joined()

        let normalized = nonCodeText.lowercased()
        let lines = nonCodeText.components(separatedBy: .newlines)
        let goalLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let ambiguityCount = countTokenMatches(in: nonCodeText, tokens: ambiguityTokens)
        let scopeLeak = containsToken(in: nonCodeText, tokens: scopeLeakTokens)

        let sectionScan = scanKnownSections(in: nonCodeText)
        let deliverableLines = sectionScan.sections[.deliverables] ?? []

        let hasEnumeratedDeliverables = deliverableLines.contains {
            $0.range(of: #"^\s*(?:\d+\.|[-*])\s+"#, options: .regularExpression) != nil
        }

        let explicitExampleCount = countOccurrences(of: "Example:", in: nonCodeText)
        let examplesCount = explicitExampleCount + originalCodeFenceBlocks

        var contradictions: [String] = []

        let concise = containsToken(in: nonCodeText, tokens: ["concise"])
        let exhaustive = containsToken(in: nonCodeText, tokens: ["exhaustive", "in its entirety", "full detail", "comprehensive"])
        if concise && exhaustive {
            contradictions.append("Concise vs exhaustive detail conflict.")
        }

        let noBrowsing = containsToken(in: nonCodeText, tokens: ["no browsing", "do not browse", "never browse", "no web", "offline only"])
        let asksBrowsing = containsToken(in: nonCodeText, tokens: ["search online", "browse the web", "web research"])
        if noBrowsing && asksBrowsing {
            contradictions.append("No-browsing instruction conflicts with web research request.")
        }

        let noCode = containsToken(in: nonCodeText, tokens: ["no code", "do not write code", "without code"])
        let asksCode = containsToken(in: nonCodeText, tokens: ["write code", "implement", "patch"])
        if noCode && asksCode {
            contradictions.append("No-code instruction conflicts with implementation request.")
        }

        let tokenEstimate = max(1, text.count / 4)
        let strongConstraintCount = countTokenMatches(in: nonCodeText, tokens: constraintMarkers)

        let outputSectionBody = (sectionScan.sections[.outputFormat] ?? []).joined(separator: "\n")
        let hasOutputTemplate = sectionScan.headings.contains(.outputFormat)
            || containsToken(in: outputSectionBody, tokens: formatMarkers + ["template", "schema"])
            || normalized.contains("output format:")

        let hasScopeBounds = containsToken(in: nonCodeText, tokens: ["in scope", "out of scope", "scope bounds", "scope", "must not", "do not", "only"])

        let unresolvedPlaceholderCount = countMatches(
            in: text,
            pattern: #"\{[a-zA-Z0-9_\-]+\}"#,
            options: []
        )

        let isVagueGoal = goalLine.count < 60 && containsToken(in: goalLine, tokens: ambiguityTokens)

        return PromptAnalysis(
            goalLine: goalLine,
            ambiguityCount: ambiguityCount,
            scopeLeak: scopeLeak,
            hasDeliverablesHeading: sectionScan.headings.contains(.deliverables),
            hasOutputFormatHeading: sectionScan.headings.contains(.outputFormat),
            hasConstraintsHeading: sectionScan.headings.contains(.constraints),
            hasQuestionsHeading: sectionScan.headings.contains(.questions),
            hasSuccessCriteriaHeading: sectionScan.headings.contains(.successCriteria),
            hasEnumeratedDeliverables: hasEnumeratedDeliverables,
            examplesCount: examplesCount,
            contradictions: contradictions,
            tokenEstimate: tokenEstimate,
            hasStrongConstraintMarkers: strongConstraintCount >= 2,
            hasOutputTemplate: hasOutputTemplate,
            hasScopeBounds: hasScopeBounds,
            unresolvedPlaceholderCount: unresolvedPlaceholderCount,
            isVagueGoal: isVagueGoal
        )
    }

    static func shieldProtectedLiterals(in text: String) -> (shielded: String, table: [String: String]) {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = RegexBank.shieldedLiteral.matches(in: text, options: [], range: nsRange)

        var table: [String: String] = [:]
        var output = text

        for (index, match) in matches.enumerated().reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let literal = String(output[range])
            let token = "__DEXCRAFT_LITERAL_\(index)__"
            output.replaceSubrange(range, with: token)
            table[token] = literal
        }

        return (output, table)
    }

    static func restoreProtectedLiterals(in text: String, table: [String: String]) -> String {
        var output = text
        // Replace longer tokens first so "__..._1__" cannot partially match "__..._10__".
        for token in table.keys.sorted(by: { $0.count > $1.count }) {
            guard let literal = table[token] else { continue }
            output = output.replacingOccurrences(of: token, with: literal)
        }
        return output
    }

    static func containsToken(in text: String, tokens: [String]) -> Bool {
        tokens.contains { token in
            countMatches(in: text, pattern: boundaryPattern(for: token), options: [.caseInsensitive]) > 0
        }
    }

    static func countTokenMatches(in text: String, tokens: [String]) -> Int {
        tokens.reduce(into: 0) { partialResult, token in
            partialResult += countMatches(in: text, pattern: boundaryPattern(for: token), options: [.caseInsensitive])
        }
    }

    static func countOccurrences(of needle: String, in text: String) -> Int {
        countMatches(in: text, pattern: NSRegularExpression.escapedPattern(for: needle), options: [.caseInsensitive])
    }

    private enum KnownSection: String, CaseIterable {
        case goal
        case context
        case constraints
        case deliverables
        case outputFormat
        case questions
        case successCriteria
    }

    private struct SectionScan {
        let sections: [KnownSection: [String]]
        let headings: Set<KnownSection>
    }

    private static func scanKnownSections(in text: String) -> SectionScan {
        let lines = text.components(separatedBy: .newlines)
        var sections: [KnownSection: [String]] = [:]
        var headings = Set<KnownSection>()
        var currentSection: KnownSection?

        for line in lines {
            if let headingMatch = parseKnownHeading(from: line) {
                currentSection = headingMatch.section
                headings.insert(headingMatch.section)
                if !headingMatch.inlineValue.isEmpty {
                    sections[headingMatch.section, default: []].append(headingMatch.inlineValue)
                }
                continue
            }

            guard let currentSection else { continue }
            sections[currentSection, default: []].append(line)
        }

        return SectionScan(sections: sections, headings: headings)
    }

    private static func parseKnownHeading(from line: String) -> (section: KnownSection, inlineValue: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutHashes = RegexBank.headingPrefix.stringByReplacingMatches(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed),
            withTemplate: ""
        )

        let lower = withoutHashes.lowercased()

        let mapping: [(aliases: [String], section: KnownSection)] = [
            (["goal", "objective", "task"], .goal),
            (["context"], .context),
            (["constraints", "constraint"], .constraints),
            (["deliverables", "deliverable"], .deliverables),
            (["output format", "output contract", "format"], .outputFormat),
            (["questions", "clarifying questions"], .questions),
            (["success criteria", "acceptance criteria"], .successCriteria)
        ]

        for entry in mapping {
            for alias in entry.aliases {
                if lower == alias {
                    return (entry.section, "")
                }

                let prefix = "\(alias):"
                if lower.hasPrefix(prefix) {
                    let idx = withoutHashes.index(withoutHashes.startIndex, offsetBy: prefix.count)
                    let inlineValue = withoutHashes[idx...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return (entry.section, inlineValue)
                }
            }
        }

        return nil
    }

    private static func boundaryPattern(for token: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        return #"(?<!\w)"# + escaped + #"(?!\w)"#
    }

    private static func countMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options
    ) -> Int {
        let cacheKey = "\(options.rawValue)|\(pattern)"
        let regex: NSRegularExpression

        regexCacheLock.lock()
        if let cached = regexCache[cacheKey] {
            regex = cached
            regexCacheLock.unlock()
        } else if let compiled = try? NSRegularExpression(pattern: pattern, options: options) {
            regexCache[cacheKey] = compiled
            regex = compiled
            regexCacheLock.unlock()
        } else {
            regexCacheLock.unlock()
            return 0
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}
