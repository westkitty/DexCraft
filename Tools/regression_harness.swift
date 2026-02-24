#!/usr/bin/env swift

/*
Local deterministic regression harness for DexCraft rewrite + validation gates.

Usage:
swift Tools/regression_harness.swift --inputs ./dexcraft_batch_inputs.json --history ./history.json
*/

import Foundation

enum PromptTarget: String, CaseIterable {
    case claude = "Claude"
    case geminiChatGPT = "Gemini/ChatGPT"
    case perplexity = "Perplexity"
    case agenticIDE = "Agentic IDE (Cursor/Windsurf/Copilot)"
}

struct EnhancementOptions: Decodable {
    var noConversationalFiller: Bool = true
    var enforceMarkdown: Bool = true
    var strictCodeOnly: Bool = false
    var preferSectionAwareParsing: Bool = true
    var includeVerificationChecklist: Bool = true
    var includeRisksAndEdgeCases: Bool = true
    var includeAlternatives: Bool = true
    var includeValidationSteps: Bool = true
    var includeRevertPlan: Bool = true
    var includeSearchVerificationRequirements: Bool = true
    var addFileTreeRequest: Bool = false
}

enum RewriteMode: String {
    case minimal
    case standard
    case aggressive
}

enum IRSectionKey {
    case goalOrTask
    case context
    case constraints
    case deliverables
}

struct PromptIR {
    let rawInput: String
    let target: PromptTarget
    let mode: RewriteMode
    let goalOrTask: String
    let context: String?
    let constraints: [String]
    let deliverables: [String]
    let outputContract: [String]
    let debugNotes: [String]
}

struct ValidationMetrics {
    let complianceScore: Double
    let ambiguityIndex: Double?
    let templateOverlap: Double?
}

struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    let metrics: ValidationMetrics
}

struct HarnessCase {
    let id: String
    let source: String
    let rawInput: String
    let target: PromptTarget
    let options: EnhancementOptions
}

struct BatchInputRecord: Decodable {
    let id: String
    let input: String
}

struct HistoryRecord: Decodable {
    let id: UUID?
    let target: String?
    let originalInput: String
    let options: EnhancementOptions?
}

let ambiguityLexicon: Set<String> = [
    "maybe", "possibly", "perhaps", "some", "various", "several",
    "generally", "roughly", "approximately", "kind", "stuff",
    "things", "probably", "might", "could", "etc"
]

struct RunResult {
    let finalPrompt: String
    let ir: PromptIR
    let validation: ValidationResult
    let fallbackNotes: [String]
}

func parseArguments() -> (inputsPath: String?, historyPath: String?) {
    var inputsPath: String?
    var historyPath: String?

    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--inputs":
            guard index + 1 < args.count else {
                fputs("Missing value for --inputs\n", stderr)
                exit(1)
            }
            inputsPath = args[index + 1]
            index += 2
        case "--history":
            guard index + 1 < args.count else {
                fputs("Missing value for --history\n", stderr)
                exit(1)
            }
            historyPath = args[index + 1]
            index += 2
        default:
            fputs("Unknown argument: \(arg)\n", stderr)
            exit(1)
        }
    }

    let fileManager = FileManager.default
    if inputsPath == nil, fileManager.fileExists(atPath: "./dexcraft_batch_inputs.json") {
        inputsPath = "./dexcraft_batch_inputs.json"
    }
    if historyPath == nil, fileManager.fileExists(atPath: "./history.json") {
        historyPath = "./history.json"
    }

    return (inputsPath, historyPath)
}

func loadCases(inputsPath: String?, historyPath: String?) -> [HarnessCase] {
    var cases: [HarnessCase] = []
    let decoder = JSONDecoder()

    if let inputsPath {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: inputsPath))
            let records = try decoder.decode([BatchInputRecord].self, from: data)
            cases.append(contentsOf: records.map {
                HarnessCase(
                    id: $0.id,
                    source: "inputs",
                    rawInput: $0.input,
                    target: .claude,
                    options: EnhancementOptions()
                )
            })
        } catch {
            fputs("Failed to load inputs from \(inputsPath): \(error)\n", stderr)
            exit(1)
        }
    }

    if let historyPath {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: historyPath))
            let records = try decoder.decode([HistoryRecord].self, from: data)
            for (index, record) in records.enumerated() {
                let target = record.target.flatMap { PromptTarget(rawValue: $0) } ?? .claude
                let id = record.id?.uuidString ?? "history-\(index + 1)"
                cases.append(
                    HarnessCase(
                        id: id,
                        source: "history",
                        rawInput: record.originalInput,
                        target: target,
                        options: record.options ?? EnhancementOptions()
                    )
                )
            }
        } catch {
            fputs("Failed to load history from \(historyPath): \(error)\n", stderr)
            exit(1)
        }
    }

    return cases
}

func normalizeBlock(_ lines: [String]) -> String {
    var start = 0
    var end = lines.count

    while start < end && lines[start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        start += 1
    }
    while end > start && lines[end - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        end -= 1
    }

    guard start < end else { return "" }

    return lines[start..<end]
        .map { $0.trimmingCharacters(in: .newlines) }
        .joined(separator: "\n")
}

func parseListLines(from lines: [String]?) -> [String] {
    guard let lines else { return [] }

    return lines
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { line in
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return line
        }
        .filter { !$0.isEmpty }
}

func dedupeCaseInsensitiveExact(_ lines: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        let normalized = trimmed.lowercased()
        if seen.insert(normalized).inserted {
            output.append(trimmed)
        }
    }

    return output
}

func normalizeLineForDedupe(_ line: String) -> String {
    line
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

func isSeparatorOnlyLine(_ line: String) -> Bool {
    guard !line.isEmpty else { return true }

    let separators = CharacterSet(charactersIn: "-_=~*•·⸻—–")
    for scalar in line.unicodeScalars {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            continue
        }
        if separators.contains(scalar) {
            continue
        }
        return false
    }

    return true
}

func countOccurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty, !haystack.isEmpty else { return 0 }

    var count = 0
    var searchRange = haystack.startIndex..<haystack.endIndex

    while let range = haystack.range(of: needle, options: [], range: searchRange) {
        count += 1
        searchRange = range.upperBound..<haystack.endIndex
    }

    return count
}

func detectIRHeading(in line: String) -> (key: IRSectionKey, inlineValue: String)? {
    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedLine.isEmpty else { return nil }

    let strippedHeadingPrefix = trimmedLine.replacingOccurrences(
        of: #"^#{1,6}\s*"#,
        with: "",
        options: .regularExpression
    )
    let normalized = strippedHeadingPrefix.lowercased()

    let candidates: [(label: String, key: IRSectionKey)] = [
        ("goal", .goalOrTask),
        ("task", .goalOrTask),
        ("context", .context),
        ("constraints", .constraints),
        ("constraint", .constraints),
        ("deliverables", .deliverables),
        ("deliverable", .deliverables)
    ]

    for candidate in candidates {
        if normalized == candidate.label {
            return (candidate.key, "")
        }

        let prefix = "\(candidate.label):"
        if normalized.hasPrefix(prefix) {
            let inlineStart = strippedHeadingPrefix.index(strippedHeadingPrefix.startIndex, offsetBy: prefix.count)
            let inlineValue = strippedHeadingPrefix[inlineStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (candidate.key, inlineValue)
        }
    }

    return nil
}

func extractConstraintLines(from lines: [String]) -> [String] {
    let prefixes = ["do not", "must", "never", "always", "keep"]
    return lines.compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        for prefix in prefixes {
            if lowered == prefix || lowered.hasPrefix("\(prefix) ") || lowered.hasPrefix("\(prefix):") {
                return trimmed
            }
        }

        return nil
    }
}

func resolveRewriteMode(autoOptimize: Bool, options: EnhancementOptions) -> RewriteMode {
    if options.includeValidationSteps || options.includeRevertPlan || options.includeVerificationChecklist {
        return .aggressive
    }

    if autoOptimize || options.enforceMarkdown || options.strictCodeOnly || options.noConversationalFiller {
        return .standard
    }

    return .minimal
}

func outputContractLines(for target: PromptTarget, mode: RewriteMode, options: EnhancementOptions) -> [String] {
    var lines: [String]

    switch target {
    case .claude:
        lines = [
            "Return only the requested sections.",
            "Keep the response concise and execution-oriented."
        ]
    case .geminiChatGPT:
        lines = [
            "Use markdown headings exactly as provided.",
            "Keep each section direct and actionable."
        ]
    case .perplexity:
        lines = [
            "Cite primary sources inline for factual claims.",
            "Call out uncertainty when evidence is incomplete."
        ]
    case .agenticIDE:
        lines = [
            "List exact files before writing edits.",
            "Apply deterministic patch steps in order.",
            "Provide runnable validation commands."
        ]
    }

    if options.noConversationalFiller {
        lines.append("Avoid conversational filler.")
    }

    switch mode {
    case .minimal:
        return target == .agenticIDE ? Array(lines.prefix(2)) : Array(lines.prefix(1))
    case .standard:
        return lines
    case .aggressive:
        if target == .agenticIDE {
            lines.append("Keep rollback scope limited to touched files.")
        } else {
            lines.append("Do not include extra sections beyond this contract.")
        }
        return lines
    }
}

func parseRawInputToIR(
    rawInput: String,
    target: PromptTarget,
    mode: RewriteMode,
    options: EnhancementOptions
) -> PromptIR {
    _ = options

    let trimmedInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = trimmedInput.components(separatedBy: .newlines)

    var sections: [IRSectionKey: [String]] = [:]
    var currentSection: IRSectionKey?
    var hasStructuredSections = false
    var debugNotes: [String] = []

    for line in lines {
        if let heading = detectIRHeading(in: line) {
            currentSection = heading.key
            hasStructuredSections = true
            if !heading.inlineValue.isEmpty {
                sections[heading.key, default: []].append(heading.inlineValue)
            }
            continue
        }

        if let currentSection {
            sections[currentSection, default: []].append(line)
        }
    }

    let goalOrTask: String
    let context: String?
    let extractedConstraints: [String]
    let extractedDeliverables: [String]

    if hasStructuredSections {
        debugNotes.append("Detected structured Goal/Context/Constraints/Deliverables headings.")
        let parsedGoal = normalizeBlock(sections[.goalOrTask] ?? [])
        goalOrTask = parsedGoal.isEmpty ? trimmedInput : parsedGoal

        let parsedContext = normalizeBlock(sections[.context] ?? [])
        context = parsedContext.isEmpty ? nil : parsedContext

        if let constraintSection = sections[.constraints] {
            extractedConstraints = parseListLines(from: constraintSection)
            debugNotes.append("Extracted constraints from explicit Constraints section.")
        } else {
            extractedConstraints = extractConstraintLines(from: lines)
            if !extractedConstraints.isEmpty {
                debugNotes.append("No Constraints section found; extracted directive-style constraint lines.")
            }
        }

        extractedDeliverables = parseListLines(from: sections[.deliverables])
    } else {
        goalOrTask = trimmedInput
        context = nil
        extractedConstraints = extractConstraintLines(from: lines)
        extractedDeliverables = []
        debugNotes.append("No structured headings found; using full input as task.")
        if !extractedConstraints.isEmpty {
            debugNotes.append("Extracted directive-style constraint lines from unstructured input.")
        }
    }

    let constraints = dedupeCaseInsensitiveExact(extractedConstraints)
    let deliverables = dedupeCaseInsensitiveExact(extractedDeliverables)

    return PromptIR(
        rawInput: trimmedInput,
        target: target,
        mode: mode,
        goalOrTask: goalOrTask,
        context: context,
        constraints: constraints,
        deliverables: deliverables,
        outputContract: outputContractLines(for: target, mode: mode, options: options),
        debugNotes: debugNotes
    )
}

func heading(_ title: String) -> String {
    "### \(title)"
}

func section(title: String, body: String) -> String {
    "\(heading(title))\n\(body)"
}

func bulletize(_ lines: [String]) -> String {
    lines.map { "- \($0)" }.joined(separator: "\n")
}

func compileFinalPrompt(from ir: PromptIR) -> String {
    switch ir.target {
    case .agenticIDE:
        let constraints = ir.constraints.isEmpty ? ["No explicit constraints provided."] : ir.constraints
        let proposedFileChanges = ir.deliverables.isEmpty ? ["Not specified in input."] : ir.deliverables

        let patchPlan = Array(ir.outputContract.prefix(min(2, ir.outputContract.count)))
        let validationCommands = ir.outputContract.count > 2
            ? Array(ir.outputContract.dropFirst(2))
            : [ir.outputContract.last ?? "Provide runnable validation commands."]

        return [
            section(title: "Goal", body: ir.goalOrTask),
            section(title: "Constraints", body: bulletize(constraints)),
            section(title: "Proposed File Changes", body: bulletize(proposedFileChanges)),
            section(title: "Patch Plan", body: bulletize(patchPlan)),
            section(title: "Validation Commands", body: bulletize(validationCommands))
        ].joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)

    case .claude, .geminiChatGPT, .perplexity:
        var sections: [String] = []
        sections.append(section(title: "Task", body: ir.goalOrTask))

        if let context = ir.context, !context.isEmpty {
            sections.append(section(title: "Context", body: context))
        }
        if !ir.constraints.isEmpty {
            sections.append(section(title: "Constraints", body: bulletize(ir.constraints)))
        }
        if !ir.deliverables.isEmpty {
            sections.append(section(title: "Deliverables", body: bulletize(ir.deliverables)))
        }
        if !ir.outputContract.isEmpty {
            sections.append(section(title: "Output Contract", body: bulletize(ir.outputContract)))
        }

        return sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func computeAmbiguityIndex(for text: String) -> Double {
    let tokens = text
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }

    guard !tokens.isEmpty else { return 0.0 }
    let vagueCount = tokens.filter { ambiguityLexicon.contains($0) }.count
    return Double(vagueCount) / Double(tokens.count)
}

func validate(finalPrompt: String, ir: PromptIR, options: EnhancementOptions) -> ValidationResult {
    _ = options

    var errors: [String] = []
    var warnings: [String] = []

    let scaffoldMarkers = [
        "### Model Family",
        "### Suggested Parameters",
        "### Applied Rules",
        "### Warnings",
        "### Legacy Canonical Draft"
    ]

    let leaked = scaffoldMarkers.filter { finalPrompt.contains($0) }
    if !leaked.isEmpty {
        errors.append("Scaffold leakage detected: \(leaked.joined(separator: ", ")).")
    }

    let preamblePhrase = "Respond only with the requested output"
    let preambleCount = countOccurrences(of: preamblePhrase, in: finalPrompt)
    if preambleCount > 1 {
        errors.append("Repeated preamble phrase detected (\(preambleCount)x).")
    }

    var seen = Set<String>()
    var duplicateLines: [String] = []
    for line in finalPrompt.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if isSeparatorOnlyLine(trimmed) { continue }

        let normalized = normalizeLineForDedupe(trimmed)
        if !seen.insert(normalized).inserted {
            duplicateLines.append(trimmed)
        }
    }
    if !duplicateLines.isEmpty {
        errors.append("Duplicate normalized lines detected: \(duplicateLines.joined(separator: " | ")).")
    }

    let retainedConstraints = ir.constraints.filter { finalPrompt.contains($0) }
    let complianceScore: Double = ir.constraints.isEmpty
        ? 1.0
        : Double(retainedConstraints.count) / Double(ir.constraints.count)

    if complianceScore < 1.0 {
        let missing = ir.constraints.filter { !finalPrompt.contains($0) }
        errors.append("Constraint retention failure: \(missing.joined(separator: " | ")).")
    }

    let templateEchoNeedle = "Use this compact example only to match structure, not to copy content."
    let hasTemplateEchoLeak = finalPrompt.contains(templateEchoNeedle) && finalPrompt.contains("### Suggested Parameters")
    if hasTemplateEchoLeak {
        errors.append("Template-echo suppression failure detected.")
    }

    let ambiguityIndex = computeAmbiguityIndex(for: finalPrompt)
    if ambiguityIndex > 0.15 {
        warnings.append(String(format: "Ambiguity index warning: %.3f (> 0.15).", ambiguityIndex))
    }

    return ValidationResult(
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
        metrics: ValidationMetrics(
            complianceScore: complianceScore,
            ambiguityIndex: ambiguityIndex,
            templateOverlap: hasTemplateEchoLeak ? 1.0 : 0.0
        )
    )
}

func runPipeline(caseItem: HarnessCase) -> RunResult {
    let initialMode = resolveRewriteMode(autoOptimize: true, options: caseItem.options)
    var fallbackNotes: [String] = ["Initial rewrite mode: \(initialMode.rawValue)"]

    var ir = parseRawInputToIR(
        rawInput: caseItem.rawInput,
        target: caseItem.target,
        mode: initialMode,
        options: caseItem.options
    )
    var finalPrompt = compileFinalPrompt(from: ir)
    var validation = validate(finalPrompt: finalPrompt, ir: ir, options: caseItem.options)

    if !validation.isValid, initialMode != .minimal {
        fallbackNotes.append("Validation failed in \(initialMode.rawValue); retrying with minimal mode.")

        let minimalIR = parseRawInputToIR(
            rawInput: caseItem.rawInput,
            target: caseItem.target,
            mode: .minimal,
            options: caseItem.options
        )
        let minimalPrompt = compileFinalPrompt(from: minimalIR)
        let minimalValidation = validate(finalPrompt: minimalPrompt, ir: minimalIR, options: caseItem.options)

        ir = minimalIR
        finalPrompt = minimalPrompt
        validation = minimalValidation
        fallbackNotes.append("Minimal mode validation: \(minimalValidation.isValid ? "passed" : "failed").")
    }

    if !validation.isValid {
        fallbackNotes.append("Validation still failing; falling back to raw input.")
        finalPrompt = caseItem.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        ir = PromptIR(
            rawInput: finalPrompt,
            target: caseItem.target,
            mode: .minimal,
            goalOrTask: finalPrompt,
            context: nil,
            constraints: [],
            deliverables: [],
            outputContract: outputContractLines(for: caseItem.target, mode: .minimal, options: caseItem.options),
            debugNotes: ["Last-resort fallback to raw input after validation failure."]
        )
        validation = validate(finalPrompt: finalPrompt, ir: ir, options: caseItem.options)
    }

    return RunResult(finalPrompt: finalPrompt, ir: ir, validation: validation, fallbackNotes: fallbackNotes)
}

let parsedArgs = parseArguments()
let cases = loadCases(inputsPath: parsedArgs.inputsPath, historyPath: parsedArgs.historyPath)

if cases.isEmpty {
    fputs("No cases loaded. Provide --inputs and/or --history, or place files in current directory.\n", stderr)
    exit(1)
}

print("Loaded \(cases.count) cases.")
if let inputsPath = parsedArgs.inputsPath { print("Inputs: \(inputsPath)") }
if let historyPath = parsedArgs.historyPath { print("History: \(historyPath)") }

var failedCount = 0
for caseItem in cases {
    let result = runPipeline(caseItem: caseItem)

    if result.validation.isValid {
        print("PASS [\(caseItem.source)] \(caseItem.id)")
    } else {
        failedCount += 1
        let firstError = result.validation.errors.first ?? "Unknown validation failure."
        print("FAIL [\(caseItem.source)] \(caseItem.id): \(firstError)")
    }
}

print("Summary: \(cases.count - failedCount) passed, \(failedCount) failed.")
exit(failedCount == 0 ? 0 : 1)
