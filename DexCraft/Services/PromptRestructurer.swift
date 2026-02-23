import Foundation

struct RestructuredPrompt {
    let goal: String
    let context: String
    let requirements: [String]
    let constraints: [String]
    let deliverables: [String]
    let openQuestions: [String]
}

enum PromptRestructurer {
    private enum Bucket {
        case goal
        case context
        case requirements
        case constraints
        case deliverables
    }

    private struct ParsedInput {
        var explicitGoal: String
        var contextLines: [String]
        var requirementLines: [String]
        var constraintLines: [String]
        var deliverableLines: [String]
        var unsectionedLines: [String]
    }

    static func restructure(
        _ rawInput: String,
        selectedTarget _: PromptTarget,
        options _: EnhancementOptions
    ) -> RestructuredPrompt {
        let normalized = normalizeInput(rawInput)
        guard !normalized.isEmpty else {
            return RestructuredPrompt(
                goal: "Define and complete the requested task precisely.",
                context: "No additional context provided.",
                requirements: [],
                constraints: [],
                deliverables: [],
                openQuestions: []
            )
        }

        var parsed = parseExplicitSections(from: normalized)
        let sentenceCandidates = sentences(from: parsed.unsectionedLines.joined(separator: " "))

        for sentence in sentenceCandidates {
            let cleaned = cleanListLine(sentence)
            guard !cleaned.isEmpty else { continue }

            switch classify(cleaned) {
            case .deliverables:
                parsed.deliverableLines.append(cleaned)
            case .constraints:
                parsed.constraintLines.append(cleaned)
            case .requirements:
                parsed.requirementLines.append(cleaned)
            case .context, .goal:
                parsed.contextLines.append(cleaned)
            }
        }

        let requirements = dedupePreservingOrder(parsed.requirementLines.map(cleanListLine).filter { !$0.isEmpty })
        let constraints = dedupePreservingOrder(parsed.constraintLines.map(cleanListLine).filter { !$0.isEmpty })
        let deliverables = dedupePreservingOrder(parsed.deliverableLines.map(cleanListLine).filter { !$0.isEmpty })

        let goal = buildGoal(explicitGoal: parsed.explicitGoal, requirements: requirements, fallbackLines: parsed.unsectionedLines)
        let context = buildContext(goal: goal, allInput: normalized, contextLines: parsed.contextLines)

        return RestructuredPrompt(
            goal: goal,
            context: context,
            requirements: requirements,
            constraints: constraints,
            deliverables: deliverables,
            openQuestions: []
        )
    }

    private static func parseExplicitSections(from input: String) -> ParsedInput {
        let lines = input.components(separatedBy: .newlines)
        var currentBucket: Bucket?
        var explicitGoal = ""
        var contextLines: [String] = []
        var requirementLines: [String] = []
        var constraintLines: [String] = []
        var deliverableLines: [String] = []
        var unsectionedLines: [String] = []

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let (bucket, inlineValue) = detectSectionHeader(in: trimmed) {
                currentBucket = bucket
                let cleanedInline = cleanListLine(inlineValue ?? "")
                guard !cleanedInline.isEmpty else { continue }

                switch bucket {
                case .goal:
                    explicitGoal = cleanedInline
                case .context:
                    contextLines.append(cleanedInline)
                case .requirements:
                    requirementLines.append(cleanedInline)
                case .constraints:
                    constraintLines.append(cleanedInline)
                case .deliverables:
                    deliverableLines.append(cleanedInline)
                }

                continue
            }

            let fragments = sentences(from: trimmed)
            if fragments.isEmpty {
                continue
            }

            if let currentBucket {
                for fragment in fragments {
                    let cleaned = cleanListLine(fragment)
                    guard !cleaned.isEmpty else { continue }

                    switch currentBucket {
                    case .goal:
                        if explicitGoal.isEmpty {
                            explicitGoal = cleaned
                        }
                    case .context:
                        contextLines.append(cleaned)
                    case .requirements:
                        requirementLines.append(cleaned)
                    case .constraints:
                        constraintLines.append(cleaned)
                    case .deliverables:
                        deliverableLines.append(cleaned)
                    }
                }
            } else {
                unsectionedLines.append(contentsOf: fragments)
            }
        }

        return ParsedInput(
            explicitGoal: explicitGoal,
            contextLines: contextLines,
            requirementLines: requirementLines,
            constraintLines: constraintLines,
            deliverableLines: deliverableLines,
            unsectionedLines: unsectionedLines
        )
    }

    private static func detectSectionHeader(in line: String) -> (Bucket, String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var candidate = trimmed
        while candidate.hasPrefix("#") {
            candidate.removeFirst()
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let (header, inline) = splitHeader(candidate)
        let key = normalizeToken(header)

        let goalKeys: Set<String> = ["goal", "objective", "task", "scenario", "mission"]
        let contextKeys: Set<String> = ["context", "background", "notes"]
        let requirementKeys: Set<String> = ["requirements", "requirement"]
        let constraintKeys: Set<String> = ["constraints", "constraint", "guardrails", "rules"]
        let deliverableKeys: Set<String> = ["deliverables", "deliverable", "output", "outputs"]

        if goalKeys.contains(key) { return (.goal, inline) }
        if contextKeys.contains(key) { return (.context, inline) }
        if requirementKeys.contains(key) { return (.requirements, inline) }
        if constraintKeys.contains(key) { return (.constraints, inline) }
        if deliverableKeys.contains(key) { return (.deliverables, inline) }

        return nil
    }

    private static func splitHeader(_ line: String) -> (String, String?) {
        if let index = line.firstIndex(of: ":") {
            let header = String(line[..<index])
            let remainder = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (header, remainder.isEmpty ? nil : remainder)
        }

        if let range = line.range(of: " - ") {
            let header = String(line[..<range.lowerBound])
            let remainder = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (header, remainder.isEmpty ? nil : remainder)
        }

        return (line, nil)
    }

    private static func sentences(from text: String) -> [String] {
        let normalized = normalizeInlineWhitespace(text)
        guard !normalized.isEmpty else { return [] }

        var working = normalized
        working = working.replacingOccurrences(of: #"[.!?;]+"#, with: "\n", options: .regularExpression)
        working = working.replacingOccurrences(
            of: #"(?i)\s+(i would like(?: to)?|we need(?: to)?|it is important that|do not|must not|must|should|add|introduce|change|make|allow|support|output|deliver|return|provide|include)\b"#,
            with: "\n$1",
            options: .regularExpression
        )

        return working
            .components(separatedBy: .newlines)
            .map(cleanListLine)
            .filter { !$0.isEmpty }
    }

    private static func classify(_ sentence: String) -> Bucket {
        let lowered = sentence.lowercased()

        if containsAny(
            lowered,
            keywords: ["output", "deliver", "return", "provide", "include", "final answer", "final output"]
        ) {
            return .deliverables
        }

        if containsAny(
            lowered,
            keywords: ["must not", "must", "do not", "never", "only", "exactly", "strict"]
        ) {
            return .constraints
        }

        if containsAny(
            lowered,
            keywords: [
                "i would like",
                "we need",
                "important",
                "add",
                "introduce",
                "change",
                "make",
                "allow",
                "support",
                "should"
            ]
        ) {
            return .requirements
        }

        if lowered.hasPrefix("context") || lowered.hasPrefix("background") || lowered.hasPrefix("notes") {
            return .context
        }

        return .context
    }

    private static func buildGoal(explicitGoal: String, requirements: [String], fallbackLines: [String]) -> String {
        let normalizedExplicit = explicitGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedExplicit.isEmpty {
            return capGoalLength(normalizedExplicit)
        }

        if let firstRequirement = requirements.first {
            return capGoalLength(toImperative(firstRequirement))
        }

        if let firstLine = fallbackLines.map(cleanListLine).first(where: { !$0.isEmpty }) {
            return capGoalLength(toImperative(firstLine))
        }

        return "Define and complete the requested task precisely."
    }

    private static func buildContext(goal: String, allInput: String, contextLines: [String]) -> String {
        var deduped = dedupePreservingOrder(
            contextLines
                .map(cleanListLine)
                .filter { !$0.isEmpty }
        )

        let normalizedGoal = normalizeToken(goal)
        deduped.removeAll { normalizeToken($0) == normalizedGoal }

        let joinedContext = deduped.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if joinedContext.isEmpty {
            return "No additional context provided."
        }

        if normalizeToken(joinedContext) == normalizeToken(allInput) {
            return "No additional context provided."
        }

        return joinedContext
    }

    private static func toImperative(_ source: String) -> String {
        var goal = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else {
            return "Define and complete the requested task precisely."
        }

        let prefixes = [
            "i would like to ",
            "i would like ",
            "we need to ",
            "we need ",
            "it is important that ",
            "please "
        ]

        let lowered = goal.lowercased()
        if let matched = prefixes.first(where: { lowered.hasPrefix($0) }) {
            goal.removeFirst(matched.count)
        }

        goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if goal.isEmpty {
            return "Define and complete the requested task precisely."
        }

        if let first = goal.first {
            goal.replaceSubrange(goal.startIndex...goal.startIndex, with: String(first).uppercased())
        }

        if goal.last != "." {
            goal.append(".")
        }

        if !goal.lowercased().hasPrefix("build ")
            && !goal.lowercased().hasPrefix("create ")
            && !goal.lowercased().hasPrefix("implement ")
            && !goal.lowercased().hasPrefix("restructure ")
            && !goal.lowercased().hasPrefix("refactor ")
            && !goal.lowercased().hasPrefix("add ")
            && !goal.lowercased().hasPrefix("update ")
            && !goal.lowercased().hasPrefix("fix ")
        {
            goal = "Implement \(goal.lowercased())"
            if goal.last != "." {
                goal.append(".")
            }
            if let first = goal.first {
                goal.replaceSubrange(goal.startIndex...goal.startIndex, with: String(first).uppercased())
            }
        }

        return goal
    }

    private static func capGoalLength(_ goal: String) -> String {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }

        let maxPrefixLength = 177
        let limited = String(trimmed.prefix(maxPrefixLength))
        if let splitIndex = limited.lastIndex(of: " "), splitIndex > limited.startIndex {
            return "\(limited[..<splitIndex])..."
        }
        return "\(limited)..."
    }

    private static func normalizeInput(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeInlineWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanListLine(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        for prefix in ["- ", "* ", "• ", "– ", "— "] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }

        if let range = value.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
            value = String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dedupePreservingOrder(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for line in lines {
            let normalized = normalizeToken(line)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                output.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return output
    }

    private static func normalizeToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func containsAny(_ haystack: String, keywords: [String]) -> Bool {
        keywords.contains { haystack.contains($0) }
    }
}
