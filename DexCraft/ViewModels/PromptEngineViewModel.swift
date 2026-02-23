import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class PromptEngineViewModel: ObservableObject {
    enum IDEExportFormat: String, CaseIterable, Identifiable {
        case cursorRules = ".cursorrules"
        case copilotInstructions = "copilot-instructions.md"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .cursorRules:
                return "Export .cursorrules"
            case .copilotInstructions:
                return "Export copilot-instructions.md"
            }
        }

        var filename: String {
            switch self {
            case .cursorRules:
                return ".cursorrules"
            case .copilotInstructions:
                return "copilot-instructions.md"
            }
        }

        var fileExtension: String {
            switch self {
            case .cursorRules:
                return "cursorrules"
            case .copilotInstructions:
                return "md"
            }
        }
    }

    @Published var selectedTarget: PromptTarget = .claude
    @Published var selectedModelFamily: ModelFamily = .openAIGPTStyle
    @Published var selectedScenarioProfile: ScenarioProfile = .ideCodingAssistant
    @Published var autoOptimizePrompt: Bool = true
    @Published var roughInput: String = "" {
        didSet { syncVariables() }
    }
    @Published private(set) var detectedVariables: [String] = []
    @Published var variableValues: [String: String] = [:]
    @Published var options: EnhancementOptions = .init()
    @Published var activeTab: WorkbenchTab = .enhance

    @Published var generatedPrompt: String = ""
    @Published var resolvedInput: String = ""
    @Published var isResultPanelVisible: Bool = false {
        didSet { onRevealStateChanged?(isResultPanelVisible) }
    }
    @Published var showDiff: Bool = false
    @Published var statusMessage: String = ""
    @Published var templateNameDraft: String = ""
    @Published var preferredIDEExportFormat: IDEExportFormat = .cursorRules
    @Published private(set) var isDetachedWindowActive: Bool = false
    @Published private(set) var optimizationAppliedRules: [String] = []
    @Published private(set) var optimizationWarnings: [String] = []
    @Published private(set) var optimizationSystemPreamble: String?
    @Published private(set) var optimizationSuggestedTemperature: Double?
    @Published private(set) var optimizationSuggestedTopP: Double?
    @Published private(set) var optimizationSuggestedMaxTokens: Int?

    @Published private(set) var templates: [PromptTemplate] = []
    @Published private(set) var history: [PromptHistoryEntry] = []
    @Published var promptLibrarySearchQuery: String = ""
    @Published var promptLibrarySelectedCategoryId: UUID?
    @Published private(set) var promptLibraryCategories: [PromptCategory] = []
    @Published private(set) var promptLibraryTags: [PromptTag] = []
    @Published private(set) var promptLibraryPrompts: [PromptLibraryItem] = []
    @Published var draftGoal: String = ""
    @Published var draftContext: String = ""
    @Published var draftConstraintsText: String = ""
    @Published var draftDeliverablesText: String = ""
    @Published var structuredPreviewFormat: Format = .plainText

    var onRevealStateChanged: ((Bool) -> Void)?
    var onDetachedWindowToggleRequested: (() -> Void)?

    private let storageManager: StorageManager
    private let promptLibraryRepository: PromptLibraryRepository
    private let offlinePromptOptimizer = OfflinePromptOptimizer()
    private let variableRegex = try? NSRegularExpression(pattern: #"\{([a-zA-Z0-9_\-]+)\}"#)

    private let noFillerConstraint = "Respond only with the requested output. Do not apologize or use conversational filler."
    private let markdownConstraint = "Use strict markdown structure and headings exactly as specified."
    private let strictCodeConstraint = "Output strict code or configuration only when code is requested."

    private var lastCanonicalPrompt: CanonicalPrompt?
    private var lastOptimizationOutput: OptimizationOutput?

    private enum InputSectionKey {
        case assumptions
        case fileTreeRequest
        case goal
        case context
        case constraints
        case deliverables
        case implementationDetails
        case verificationChecklist
        case risksAndEdgeCases
        case alternatives
        case validationSteps
        case revertPlan
    }

    private struct ParsedPromptInput {
        var assumptions: [String]
        var fileTreeRequest: [String]
        var goal: String
        var context: String
        var constraints: [String]
        var deliverables: [String]
        var implementationDetails: [String]
        var verificationChecklist: [String]
        var risksAndEdgeCases: [String]
        var alternatives: [String]
        var validationSteps: [String]
        var revertPlan: [String]
    }

    private struct CanonicalPrompt {
        var assumptions: [String]
        var fileTreeRequest: [String]
        var goal: String
        var context: String
        var constraints: [String]
        var deliverables: [String]
        var implementationDetails: [String]
        var verificationChecklist: [String]
        var risksAndEdgeCases: [String]
        var alternatives: [String]
        var validationSteps: [String]
        var revertPlan: [String]
    }

    init(
        storageManager: StorageManager = StorageManager(),
        promptLibraryRepository: PromptLibraryRepository = PromptLibraryRepository()
    ) {
        self.storageManager = storageManager
        self.promptLibraryRepository = promptLibraryRepository
        templates = storageManager.loadTemplates()
        history = storageManager.loadHistory()

        let defaultTemplates = PromptTemplate.defaultPresets()
        if templates.isEmpty {
            templates = defaultTemplates
            storageManager.saveTemplates(templates)
        } else {
            var knownTemplateNames = Set(
                templates.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            )
            let missingDefaults = defaultTemplates.filter { preset in
                let key = preset.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return knownTemplateNames.insert(key).inserted
            }

            if !missingDefaults.isEmpty {
                templates.append(contentsOf: missingDefaults)
                storageManager.saveTemplates(templates)
            }
        }

        refreshPromptLibraryState()
    }

    var qualityChecks: [QualityCheck] {
        let variablesComplete = detectedVariables.allSatisfy {
            !(variableValues[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if autoOptimizePrompt {
            guard let output = lastOptimizationOutput, !generatedPrompt.isEmpty else {
                return [
                    QualityCheck(title: "Optimized Prompt Present", passed: false),
                    QualityCheck(title: "Applied Rules Present", passed: false),
                    QualityCheck(title: "Variables Filled", passed: variablesComplete)
                ]
            }

            let hasPrompt = !output.optimizedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasRules = !output.appliedRules.isEmpty
            let hasCLIConstraints = selectedScenarioProfile != .cliAssistant || output.optimizedPrompt.localizedCaseInsensitiveContains("copy/paste")
            let hasJSONContract = selectedScenarioProfile != .jsonStructuredOutput || output.optimizedPrompt.localizedCaseInsensitiveContains("json")
            let hasToolFallback = selectedScenarioProfile != .toolUsingAgent ||
                output.appliedRules.contains(where: { $0.localizedCaseInsensitiveContains("tool") })

            return [
                QualityCheck(title: "Optimized Prompt Present", passed: hasPrompt),
                QualityCheck(title: "Applied Rules Present", passed: hasRules),
                QualityCheck(title: "CLI Constraints Applied", passed: hasCLIConstraints),
                QualityCheck(title: "JSON Contract Applied", passed: hasJSONContract),
                QualityCheck(title: "Tool Strategy Applied", passed: hasToolFallback),
                QualityCheck(title: "Variables Filled", passed: variablesComplete)
            ]
        }

        guard let canonical = lastCanonicalPrompt, !generatedPrompt.isEmpty else {
            return [
                QualityCheck(title: "Goal Section Present", passed: false),
                QualityCheck(title: "Constraints Section Present", passed: false),
                QualityCheck(title: "Section Order Valid", passed: false),
                QualityCheck(title: "Variables Filled", passed: variablesComplete)
            ]
        }

        let hasAssumptions = !canonical.assumptions.isEmpty
        let goalText = canonical.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasGoal = !goalText.isEmpty
        let hasSemanticGoal = hasGoal && !isLikelyHeadingToken(goalText)
        let hasContext = !canonical.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasConstraints = !canonical.constraints.isEmpty
        let hasDeliverables = !canonical.deliverables.isEmpty
        let hasImplementationDetails = !canonical.implementationDetails.isEmpty

        let hasFileTree = !options.addFileTreeRequest || !canonical.fileTreeRequest.isEmpty
        let hasVerificationChecklist = !options.includeVerificationChecklist || !canonical.verificationChecklist.isEmpty

        let dedupedConstraints = dedupeLines(canonical.constraints)
        let noDuplicateConstraints = dedupedConstraints.count == canonical.constraints.count
        let noDuplicateNoFiller = countOccurrences(
            of: normalizeLineForDedupe(noFillerConstraint),
            in: normalizeLineForDedupe(generatedPrompt)
        ) <= 1

        let hasPerplexitySearchRequirements = selectedTarget != .perplexity || !options.includeSearchVerificationRequirements ||
            canonical.constraints.contains(where: {
                let normalized = normalizeLineForDedupe($0)
                return normalized.contains("cite primary sources") || normalized.contains("verify facts")
            })

        let hasClaudeXMLTags = selectedTarget != .claude || hasClaudeRequiredTags(in: generatedPrompt)
        let hasAgenticBuildRun = selectedTarget != .agenticIDE || generatedPrompt.contains(heading("Build/Run Commands"))
        let hasAgenticGitRevert = selectedTarget != .agenticIDE || generatedPrompt.contains(heading("Git/Revert Plan"))
        let sectionOrderValid = selectedTarget == .claude
            ? hasClaudeTagOrder(in: generatedPrompt)
            : hasRequiredSectionOrder(in: generatedPrompt)

        return [
            QualityCheck(title: "Assumptions Section Present", passed: hasAssumptions),
            QualityCheck(title: "Goal Section Present", passed: hasGoal),
            QualityCheck(title: "Goal Content Valid", passed: hasSemanticGoal),
            QualityCheck(title: "Context Section Present", passed: hasContext),
            QualityCheck(title: "Constraints Section Present", passed: hasConstraints),
            QualityCheck(title: "Deliverables Section Present", passed: hasDeliverables),
            QualityCheck(title: "Implementation Details Present", passed: hasImplementationDetails),
            QualityCheck(title: "File Tree Section Present", passed: hasFileTree),
            QualityCheck(title: "Verification Checklist Present", passed: hasVerificationChecklist),
            QualityCheck(title: "No Duplicate Constraints", passed: noDuplicateConstraints),
            QualityCheck(title: "No Duplicate No-Filler Line", passed: noDuplicateNoFiller),
            QualityCheck(title: "Perplexity Verification Rules Applied", passed: hasPerplexitySearchRequirements),
            QualityCheck(title: "Claude XML Tags Present", passed: hasClaudeXMLTags),
            QualityCheck(title: "Agentic Build/Run Section Present", passed: hasAgenticBuildRun),
            QualityCheck(title: "Agentic Git/Revert Section Present", passed: hasAgenticGitRevert),
            QualityCheck(title: "Section Order Valid", passed: sectionOrderValid),
            QualityCheck(title: "Variables Filled", passed: variablesComplete)
        ]
    }

    func bindingForVariable(_ name: String) -> Binding<String> {
        Binding(
            get: { self.variableValues[name, default: ""] },
            set: { self.variableValues[name] = $0 }
        )
    }

    func forgePrompt() {
        let cleaned = roughInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusMessage = "Enter rough input before forging."
            return
        }

        statusMessage = ""
        resolvedInput = substituteVariables(in: cleaned)

        let parsed = parseInputSections(from: resolvedInput)
        let canonical = buildCanonicalPrompt(from: parsed, target: selectedTarget)
        let basePrompt = renderPrompt(target: selectedTarget, canonical: canonical)

        if autoOptimizePrompt {
            let output = offlinePromptOptimizer.optimize(
                OptimizationInput(
                    rawUserPrompt: resolvedInput,
                    modelFamily: selectedModelFamily,
                    scenario: selectedScenarioProfile,
                    userOverrides: nil
                )
            )
            lastOptimizationOutput = output
            optimizationAppliedRules = output.appliedRules
            optimizationWarnings = output.warnings
            optimizationSystemPreamble = output.systemPreamble
            optimizationSuggestedTemperature = output.suggestedTemperature
            optimizationSuggestedTopP = output.suggestedTopP
            optimizationSuggestedMaxTokens = output.suggestedMaxTokens
            generatedPrompt = renderOptimizationPackage(basePrompt: basePrompt, output: output)
        } else {
            generatedPrompt = basePrompt
            clearOptimizationMetadata()
        }

        lastCanonicalPrompt = canonical
        isResultPanelVisible = true

        let entry = PromptHistoryEntry(
            target: selectedTarget,
            originalInput: roughInput,
            generatedPrompt: generatedPrompt,
            options: options,
            variables: variableValues
        )

        history.insert(entry, at: 0)
        history = Array(history.prefix(50))
        storageManager.saveHistory(history)
    }

    func copyToClipboard() {
        guard !generatedPrompt.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(generatedPrompt, forType: .string)
        statusMessage = "Prompt copied to clipboard."
    }

    func exportOptimizedPromptAsMarkdown() {
        guard !generatedPrompt.isEmpty else {
            statusMessage = "Forge a prompt before exporting."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dexcraft-optimized-prompt.md"
        panel.canCreateDirectories = true

        if #available(macOS 11.0, *) {
            if let contentType = UTType(filenameExtension: "md") {
                panel.allowedContentTypes = [contentType]
            }
        } else {
            panel.allowedFileTypes = ["md"]
        }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try generatedPrompt.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Exported: \(url.path)"
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportForIDE(_ format: IDEExportFormat) {
        guard !generatedPrompt.isEmpty else {
            statusMessage = "Forge a prompt before exporting."
            return
        }

        if options.addFileTreeRequest,
           !generatedPrompt.contains(heading("File Tree Request (Before Implementation Details)")) {
            statusMessage = "Export blocked: File Tree Request section is missing."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = format.filename
        panel.canCreateDirectories = true

        if #available(macOS 11.0, *) {
            if let contentType = UTType(filenameExtension: format.fileExtension) {
                panel.allowedContentTypes = [contentType]
            }
        } else {
            panel.allowedFileTypes = [format.fileExtension]
        }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try generatedPrompt.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Exported: \(url.path)"
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func saveCurrentAsTemplate() {
        let name = templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = roughInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            statusMessage = "Template name is required."
            return
        }

        guard !body.isEmpty else {
            statusMessage = "Cannot save an empty template."
            return
        }

        if let index = templates.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            templates[index].content = roughInput
            templates[index].target = selectedTarget
        } else {
            templates.insert(PromptTemplate(name: name, content: roughInput, target: selectedTarget), at: 0)
        }

        templateNameDraft = ""
        storageManager.saveTemplates(templates)
        statusMessage = "Template saved."
    }

    func applyTemplate(_ template: PromptTemplate) {
        roughInput = template.content
        selectedTarget = template.target
        activeTab = .enhance
        statusMessage = "Template loaded: \(template.name)"
    }

    func deleteTemplate(_ template: PromptTemplate) {
        templates.removeAll { $0.id == template.id }
        storageManager.saveTemplates(templates)
    }

    func loadHistoryEntry(_ entry: PromptHistoryEntry) {
        roughInput = entry.originalInput
        selectedTarget = entry.target
        options = entry.options
        variableValues = entry.variables
        resolvedInput = substituteVariables(in: roughInput)
        generatedPrompt = entry.generatedPrompt

        let parsed = parseInputSections(from: resolvedInput)
        lastCanonicalPrompt = buildCanonicalPrompt(from: parsed, target: selectedTarget)
        clearOptimizationMetadata()

        isResultPanelVisible = true
        statusMessage = "Loaded history entry."
    }

    func clearHistory() {
        history.removeAll()
        storageManager.saveHistory(history)
        statusMessage = "History cleared."
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var filteredPromptLibraryPrompts: [PromptLibraryItem] {
        promptLibraryRepository.searchPrompts(
            query: promptLibrarySearchQuery,
            categoryId: promptLibrarySelectedCategoryId
        )
    }

    var structuredDraft: Draft {
        Draft(
            goal: draftGoal,
            context: draftContext,
            constraints: parseStructuredList(from: draftConstraintsText),
            deliverables: parseStructuredList(from: draftDeliverablesText)
        )
    }

    var structuredPreview: String {
        buildPreview(draft: structuredDraft, format: structuredPreviewFormat)
    }

    func createPromptLibraryCategory(name: String) {
        guard promptLibraryRepository.createCategory(name: name) != nil else {
            statusMessage = "Category name is required."
            return
        }

        refreshPromptLibraryState()
        statusMessage = "Category saved."
    }

    func deletePromptLibraryCategory(_ category: PromptCategory) {
        promptLibraryRepository.deleteCategory(id: category.id)

        if promptLibrarySelectedCategoryId == category.id {
            promptLibrarySelectedCategoryId = nil
        }

        refreshPromptLibraryState()
        statusMessage = "Category removed."
    }

    func createPromptLibraryTag(name: String) {
        guard promptLibraryRepository.createTag(name: name) != nil else {
            statusMessage = "Tag name is required."
            return
        }

        refreshPromptLibraryState()
        statusMessage = "Tag saved."
    }

    func createPromptLibraryPrompt(title: String, body: String, categoryId: UUID? = nil) {
        guard promptLibraryRepository.createPrompt(title: title, body: body, categoryId: categoryId) != nil else {
            statusMessage = "Prompt title is required."
            return
        }

        refreshPromptLibraryState()
        statusMessage = "Prompt saved to library."
    }

    func updatePromptLibraryPromptCategory(promptId: UUID, categoryId: UUID?) {
        promptLibraryRepository.updatePromptCategory(promptId: promptId, categoryId: categoryId)
        refreshPromptLibraryState()
    }

    func updatePromptLibraryPromptTags(promptId: UUID, tagIds: [UUID]) {
        promptLibraryRepository.updatePromptTags(promptId: promptId, tagIds: tagIds)
        refreshPromptLibraryState()
    }

    func deletePromptLibraryPrompt(promptId: UUID) {
        promptLibraryRepository.deletePrompt(id: promptId)
        refreshPromptLibraryState()
        statusMessage = "Prompt removed."
    }

    func promptLibraryCategoryName(for prompt: PromptLibraryItem) -> String {
        promptLibraryRepository.categoryName(for: prompt.categoryId)
    }

    func promptLibraryTagNames(for prompt: PromptLibraryItem) -> [String] {
        promptLibraryRepository.tagNames(for: prompt.tagIds)
    }

    func diffText() -> String {
        let original = resolvedInput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let enhanced = generatedPrompt
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let maxLines = max(original.count, enhanced.count)
        var lines: [String] = []

        for index in 0..<maxLines {
            let oldLine = index < original.count ? original[index] : ""
            let newLine = index < enhanced.count ? enhanced[index] : ""

            if oldLine == newLine {
                lines.append("  \(oldLine)")
            } else {
                if !oldLine.isEmpty {
                    lines.append("- \(oldLine)")
                }
                if !newLine.isEmpty {
                    lines.append("+ \(newLine)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    func requestDetachedWindowToggle() {
        onDetachedWindowToggleRequested?()
    }

    func setDetachedWindowActive(_ active: Bool) {
        isDetachedWindowActive = active
    }

    var optimizationParameterSummary: String {
        guard autoOptimizePrompt else {
            return "Auto-optimize is disabled."
        }

        guard lastOptimizationOutput != nil else {
            return "No optimizer suggestions available."
        }

        let temperature = optimizationSuggestedTemperature.map { String(format: "%.2f", $0) } ?? "n/a"
        let topP = optimizationSuggestedTopP.map { String(format: "%.2f", $0) } ?? "n/a"
        let maxTokens = optimizationSuggestedMaxTokens.map(String.init) ?? "n/a"
        return "temperature=\(temperature), top_p=\(topP), max_tokens=\(maxTokens)"
    }

    private func refreshPromptLibraryState() {
        promptLibraryCategories = promptLibraryRepository.categories
        promptLibraryTags = promptLibraryRepository.tags
        promptLibraryPrompts = promptLibraryRepository.prompts
    }

    private func parseStructuredList(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncVariables() {
        guard let variableRegex else {
            detectedVariables = []
            variableValues = [:]
            return
        }

        let nsRange = NSRange(roughInput.startIndex..<roughInput.endIndex, in: roughInput)
        let matches = variableRegex.matches(in: roughInput, options: [], range: nsRange)

        var ordered: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: roughInput)
            else {
                continue
            }

            let variable = String(roughInput[range])
            if seen.insert(variable).inserted {
                ordered.append(variable)
            }
        }

        let existing = variableValues
        detectedVariables = ordered
        variableValues = Dictionary(uniqueKeysWithValues: ordered.map { key in
            (key, existing[key, default: ""])
        })
    }

    private func substituteVariables(in text: String) -> String {
        var output = text

        for variable in detectedVariables {
            let token = "{\(variable)}"
            let replacement = variableValues[variable]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let replacement, !replacement.isEmpty {
                output = output.replacingOccurrences(of: token, with: replacement)
            }
        }

        return output
    }

    private func parseInputSections(from input: String) -> ParsedPromptInput {
        guard options.preferSectionAwareParsing else {
            return fallbackParsedInput(from: input)
        }

        let lines = input.components(separatedBy: .newlines)
        var sections: [InputSectionKey: [String]] = [:]
        var currentSection: InputSectionKey?
        var sawCoreHeading = false
        var preHeadingLines: [String] = []

        for line in lines {
            if let heading = detectHeading(in: line) {
                currentSection = heading.key
                if [.goal, .context, .constraints, .deliverables].contains(heading.key) {
                    sawCoreHeading = true
                }

                if !heading.inlineValue.isEmpty {
                    sections[heading.key, default: []].append(heading.inlineValue)
                }

                continue
            }

            if let currentSection {
                sections[currentSection, default: []].append(line)
            } else {
                preHeadingLines.append(line)
            }
        }

        guard sawCoreHeading else {
            return fallbackParsedInput(from: input)
        }

        let leadingContext = normalizeBlock(preHeadingLines)

        let parsedGoal = normalizeBlock(sections[.goal] ?? [])
        var parsedContext = normalizeBlock(sections[.context] ?? [])

        if !leadingContext.isEmpty {
            if parsedContext.isEmpty {
                parsedContext = leadingContext
            } else {
                parsedContext = "\(leadingContext)\n\n\(parsedContext)"
            }
        }

        return ParsedPromptInput(
            assumptions: parseListLines(from: sections[.assumptions]),
            fileTreeRequest: parseListLines(from: sections[.fileTreeRequest]),
            goal: parsedGoal,
            context: parsedContext,
            constraints: parseListLines(from: sections[.constraints]),
            deliverables: parseListLines(from: sections[.deliverables]),
            implementationDetails: parseListLines(from: sections[.implementationDetails]),
            verificationChecklist: parseListLines(from: sections[.verificationChecklist]),
            risksAndEdgeCases: parseListLines(from: sections[.risksAndEdgeCases]),
            alternatives: parseListLines(from: sections[.alternatives]),
            validationSteps: parseListLines(from: sections[.validationSteps]),
            revertPlan: parseListLines(from: sections[.revertPlan])
        )
    }

    private func fallbackParsedInput(from input: String) -> ParsedPromptInput {
        let fallback = fallbackGoalAndContext(from: input)
        return ParsedPromptInput(
            assumptions: [],
            fileTreeRequest: [],
            goal: fallback.goal,
            context: fallback.context,
            constraints: [],
            deliverables: [],
            implementationDetails: [],
            verificationChecklist: [],
            risksAndEdgeCases: [],
            alternatives: [],
            validationSteps: [],
            revertPlan: []
        )
    }

    private func buildCanonicalPrompt(from parsed: ParsedPromptInput, target: PromptTarget) -> CanonicalPrompt {
        let assumptions = dedupeLines(
            parsed.assumptions.isEmpty
                ? [
                    "State assumptions explicitly where requirements are incomplete.",
                    "Keep outputs deterministic and implementation-oriented."
                ]
                : parsed.assumptions
        )

        let fileTreeRequest = options.addFileTreeRequest
            ? dedupeLines(
                parsed.fileTreeRequest.isEmpty
                    ? [
                        "Propose exact files to create/update before implementation details.",
                        "Include absolute or workspace-relative paths for each file."
                    ]
                    : parsed.fileTreeRequest
            )
            : []

        var constraints = parsed.constraints
        constraints.append(contentsOf: optionConstraintLines())
        constraints.append(contentsOf: targetConstraintLines(for: target))

        if target == .perplexity && options.includeSearchVerificationRequirements {
            constraints.append("Cite primary sources for factual claims.")
            constraints.append("Verify facts before synthesis and flag unresolved uncertainty.")
        }

        constraints = dedupeLines(constraints)

        var deliverables = parsed.deliverables
        if deliverables.isEmpty {
            deliverables = [
                "Complete every requested deliverable with concrete output.",
                "Call out assumptions before implementation details."
            ]
        }
        deliverables = dedupeLines(deliverables)

        let implementationDetails = dedupeLines(
            parsed.implementationDetails.isEmpty
                ? defaultImplementationDetails(for: target)
                : parsed.implementationDetails
        )

        let verificationChecklist = options.includeVerificationChecklist
            ? dedupeLines(
                parsed.verificationChecklist.isEmpty
                    ? [
                        "[ ] Required sections present in canonical order.",
                        "[ ] Constraints are deduplicated and deterministic.",
                        "[ ] Variable placeholders are fully resolved."
                    ]
                    : parsed.verificationChecklist
            )
            : []

        let risksAndEdgeCases = options.includeRisksAndEdgeCases
            ? dedupeLines(
                parsed.risksAndEdgeCases.isEmpty
                    ? [
                        "Ambiguous requirements can produce hidden scope changes.",
                        "Unstated environment assumptions may break reproducibility."
                    ]
                    : parsed.risksAndEdgeCases
            )
            : []

        let alternatives = options.includeAlternatives
            ? dedupeLines(
                parsed.alternatives.isEmpty
                    ? [
                        "Use an incremental implementation-first pass followed by hardening.",
                        "Use template/preset-driven prompts for repeatable tasks."
                    ]
                    : parsed.alternatives
            )
            : []

        let validationSteps = options.includeValidationSteps
            ? dedupeLines(
                parsed.validationSteps.isEmpty
                    ? [
                        "Run build/test commands in deterministic order.",
                        "Verify section order and constraint deduplication in generated output."
                    ]
                    : parsed.validationSteps
            )
            : []

        let revertPlan = options.includeRevertPlan
            ? dedupeLines(
                parsed.revertPlan.isEmpty
                    ? [
                        "Revert only changed files if validation fails.",
                        "Prefer rollback commits over history rewrites on shared branches."
                    ]
                    : parsed.revertPlan
            )
            : []

        let normalizedGoal = parsed.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = normalizedGoal.isEmpty || isLikelyHeadingToken(normalizedGoal)
            ? "Define and complete the requested task precisely."
            : normalizedGoal

        let context = parsed.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No additional context provided."
            : parsed.context.trimmingCharacters(in: .whitespacesAndNewlines)

        return CanonicalPrompt(
            assumptions: assumptions,
            fileTreeRequest: fileTreeRequest,
            goal: goal,
            context: context,
            constraints: constraints,
            deliverables: deliverables,
            implementationDetails: implementationDetails,
            verificationChecklist: verificationChecklist,
            risksAndEdgeCases: risksAndEdgeCases,
            alternatives: alternatives,
            validationSteps: validationSteps,
            revertPlan: revertPlan
        )
    }

    private func renderPrompt(target: PromptTarget, canonical: CanonicalPrompt) -> String {
        let canonicalMarkdown = renderCanonicalMarkdown(from: canonical)

        switch target {
        case .claude:
            return renderClaudePrompt(from: canonical)
        case .geminiChatGPT:
            return canonicalMarkdown
        case .perplexity:
            return canonicalMarkdown
        case .agenticIDE:
            return """
            \(canonicalMarkdown)

            ### Agentic IDE Operational Blocks
            #### Proposed File Changes
            - List exact files to create or update before making code edits.

            #### Patch Plan
            - Describe deterministic edit steps in command execution order.

            #### Execution Order
            - Run preflight checks before edits, then build/validate after edits.

            ### Build/Run Commands
            - List commands in execution order.
            - Use reproducible commands and avoid destructive git operations unless explicitly approved.

            ### Git/Revert Plan
            - Describe commit strategy and rollback path.
            - Do not rewrite history unless asked.

            #### Validation Commands
            - Provide build/test commands with expected outcomes.

            #### Rollback Plan
            - Provide minimal rollback instructions for modified files.
            """
        }
    }

    private func renderCanonicalMarkdown(from canonical: CanonicalPrompt) -> String {
        var sections: [String] = []

        sections.append(section(title: "Assumptions", body: bulletize(canonical.assumptions)))

        if options.addFileTreeRequest {
            sections.append(section(title: "File Tree Request (Before Implementation Details)", body: bulletize(canonical.fileTreeRequest)))
        }

        sections.append(section(title: "Goal", body: canonical.goal))
        sections.append(section(title: "Context", body: canonical.context))
        sections.append(section(title: "Constraints", body: bulletize(canonical.constraints)))
        sections.append(section(title: "Deliverables", body: bulletize(canonical.deliverables)))
        sections.append(section(title: "Implementation Details", body: bulletize(canonical.implementationDetails)))

        if options.includeVerificationChecklist {
            sections.append(section(title: "Verification Checklist (Pass/Fail)", body: checkboxize(canonical.verificationChecklist)))
        }

        if options.includeRisksAndEdgeCases {
            sections.append(section(title: "Risks / Edge Cases", body: bulletize(canonical.risksAndEdgeCases)))
        }

        if options.includeAlternatives {
            sections.append(section(title: "Alternatives", body: bulletize(canonical.alternatives)))
        }

        if options.includeValidationSteps {
            sections.append(section(title: "Validation Steps", body: bulletize(canonical.validationSteps)))
        }

        if options.includeRevertPlan {
            sections.append(section(title: "Revert Plan", body: bulletize(canonical.revertPlan)))
        }

        return sections.joined(separator: "\n\n")
    }

    private func hasRequiredSectionOrder(in prompt: String) -> Bool {
        var headings: [String] = [
            heading("Assumptions")
        ]

        if options.addFileTreeRequest {
            headings.append(heading("File Tree Request (Before Implementation Details)"))
        }

        headings.append(contentsOf: [
            heading("Goal"),
            heading("Context"),
            heading("Constraints"),
            heading("Deliverables"),
            heading("Implementation Details")
        ])

        if options.includeVerificationChecklist {
            headings.append(heading("Verification Checklist (Pass/Fail)"))
        }

        if options.includeRisksAndEdgeCases {
            headings.append(heading("Risks / Edge Cases"))
        }

        if options.includeAlternatives {
            headings.append(heading("Alternatives"))
        }

        if options.includeValidationSteps {
            headings.append(heading("Validation Steps"))
        }

        if options.includeRevertPlan {
            headings.append(heading("Revert Plan"))
        }

        var searchRange = prompt.startIndex..<prompt.endIndex
        for requiredHeading in headings {
            guard let range = prompt.range(of: requiredHeading, options: [], range: searchRange) else {
                return false
            }
            searchRange = range.upperBound..<prompt.endIndex
        }

        return true
    }

    private func hasClaudeRequiredTags(in prompt: String) -> Bool {
        [
            "<objective>", "</objective>",
            "<context>", "</context>",
            "<constraints>", "</constraints>",
            "<deliverables>", "</deliverables>"
        ].allSatisfy(prompt.contains)
    }

    private func hasClaudeTagOrder(in prompt: String) -> Bool {
        let tags = ["<objective>", "<context>", "<constraints>", "<deliverables>"]
        var searchRange = prompt.startIndex..<prompt.endIndex

        for tag in tags {
            guard let range = prompt.range(of: tag, options: [], range: searchRange) else {
                return false
            }
            searchRange = range.upperBound..<prompt.endIndex
        }

        return true
    }

    private func detectHeading(in line: String) -> (key: InputSectionKey, inlineValue: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutHashes = trimmed.replacingOccurrences(
            of: #"^#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )

        guard !withoutHashes.isEmpty else { return nil }

        let headingName: String
        let inlineValue: String

        if let colonIndex = withoutHashes.firstIndex(of: ":") {
            let candidate = String(withoutHashes[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let matchedKey = headingKey(for: candidate) else {
                return nil
            }

            let value = String(withoutHashes[withoutHashes.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (matchedKey, value)
        }

        headingName = withoutHashes.trimmingCharacters(in: .whitespacesAndNewlines)
        inlineValue = ""

        guard let key = headingKey(for: headingName) else {
            return nil
        }

        return (key, inlineValue)
    }

    private func headingKey(for rawHeading: String) -> InputSectionKey? {
        let normalized = rawHeading
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        switch normalized {
        case "assumptions":
            return .assumptions
        case "file tree request", "file tree request (before implementation details)":
            return .fileTreeRequest
        case "goal", "objective":
            return .goal
        case "context":
            return .context
        case "constraints":
            return .constraints
        case "deliverables":
            return .deliverables
        case "implementation details":
            return .implementationDetails
        case "verification checklist", "verification checklist (pass/fail)":
            return .verificationChecklist
        case "risks / edge cases", "risks and edge cases", "risks", "edge cases":
            return .risksAndEdgeCases
        case "alternatives":
            return .alternatives
        case "validation steps":
            return .validationSteps
        case "revert plan", "rollback plan":
            return .revertPlan
        default:
            return nil
        }
    }

    private func fallbackGoalAndContext(from input: String) -> (goal: String, context: String) {
        let lines = input.components(separatedBy: .newlines)

        guard let firstNonEmpty = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return ("Define and complete the requested task precisely.", "")
        }

        var remaining: [String] = []
        var firstLineConsumed = false

        for line in lines {
            if !firstLineConsumed,
               line.trimmingCharacters(in: .whitespacesAndNewlines) == firstNonEmpty.trimmingCharacters(in: .whitespacesAndNewlines) {
                firstLineConsumed = true
                continue
            }
            if firstLineConsumed {
                remaining.append(line)
            }
        }

        return (
            firstNonEmpty.trimmingCharacters(in: .whitespacesAndNewlines),
            normalizeBlock(remaining)
        )
    }

    private func normalizeBlock(_ lines: [String]) -> String {
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

    private func optionConstraintLines() -> [String] {
        var lines: [String] = []

        if options.noConversationalFiller {
            lines.append(noFillerConstraint)
        }

        if options.enforceMarkdown {
            lines.append(markdownConstraint)
        }

        if options.strictCodeOnly {
            lines.append(strictCodeConstraint)
        }

        return lines
    }

    private func targetConstraintLines(for target: PromptTarget) -> [String] {
        switch target {
        case .claude:
            return ["Optimize structure for direct consumption by Claude."]
        case .geminiChatGPT:
            return ["Use strict markdown hierarchy with concise, actionable language."]
        case .perplexity:
            return ["Optimize for search-grounded synthesis with explicit verification." ]
        case .agenticIDE:
            return ["Use deterministic file-writing instructions with explicit command order."]
        }
    }

    private func defaultImplementationDetails(for target: PromptTarget) -> [String] {
        switch target {
        case .claude:
            return [
                "Use concise, high-signal instructions with deterministic section ordering.",
                "Preserve user constraints and deliverables without semantic drift."
            ]
        case .geminiChatGPT:
            return [
                "Use strict markdown heading structure and concise bullet points.",
                "Keep the response limited to requested deliverables and checks."
            ]
        case .perplexity:
            return [
                "Separate confirmed facts from assumptions before final synthesis.",
                "Prefer primary sources and explicitly annotate unresolved uncertainty."
            ]
        case .agenticIDE:
            return [
                "Define file changes before code edits and keep execution order deterministic.",
                "Provide build/test validation commands and rollback steps tied to touched files."
            ]
        }
    }

    private func parseListLines(from lines: [String]?) -> [String] {
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

    private func dedupeLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var deduped: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = normalizeLineForDedupe(trimmed)
            if seen.insert(normalized).inserted {
                deduped.append(trimmed)
            }
        }

        return deduped
    }

    private func normalizeLineForDedupe(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func isLikelyHeadingToken(_ value: String) -> Bool {
        value.range(of: #"^#{1,6}\s+\S+"#, options: .regularExpression) != nil
    }

    private func renderClaudePrompt(from canonical: CanonicalPrompt) -> String {
        """
        <objective>
        \(canonical.goal)
        </objective>

        <context>
        \(renderClaudeContextBlock(from: canonical))
        </context>

        <constraints>
        \(bulletize(canonical.constraints))
        </constraints>

        <deliverables>
        \(renderClaudeDeliverablesBlock(from: canonical))
        </deliverables>
        """
    }

    private func renderClaudeContextBlock(from canonical: CanonicalPrompt) -> String {
        var blocks: [String] = []
        blocks.append("Assumptions:\n\(bulletize(canonical.assumptions))")

        if options.addFileTreeRequest {
            blocks.append("File Tree Request (Before Implementation Details):\n\(bulletize(canonical.fileTreeRequest))")
        }

        blocks.append("Context:\n\(canonical.context)")
        return blocks.joined(separator: "\n\n")
    }

    private func renderClaudeDeliverablesBlock(from canonical: CanonicalPrompt) -> String {
        var blocks: [String] = []
        blocks.append("Deliverables:\n\(bulletize(canonical.deliverables))")
        blocks.append("Implementation Details:\n\(bulletize(canonical.implementationDetails))")

        if options.includeVerificationChecklist {
            blocks.append("Verification Checklist (Pass/Fail):\n\(checkboxize(canonical.verificationChecklist))")
        }

        if options.includeRisksAndEdgeCases {
            blocks.append("Risks / Edge Cases:\n\(bulletize(canonical.risksAndEdgeCases))")
        }

        if options.includeAlternatives {
            blocks.append("Alternatives:\n\(bulletize(canonical.alternatives))")
        }

        if options.includeValidationSteps {
            blocks.append("Validation Steps:\n\(bulletize(canonical.validationSteps))")
        }

        if options.includeRevertPlan {
            blocks.append("Revert Plan:\n\(bulletize(canonical.revertPlan))")
        }

        return blocks.joined(separator: "\n\n")
    }

    private func section(title: String, body: String) -> String {
        "\(heading(title))\n\(body)"
    }

    private func heading(_ title: String) -> String {
        "### \(title)"
    }

    private func bulletize(_ lines: [String]) -> String {
        lines.map { "- \($0)" }.joined(separator: "\n")
    }

    private func checkboxize(_ lines: [String]) -> String {
        lines.map { line in
            if line.hasPrefix("[ ]") {
                return "- \(line)"
            }

            if line.hasPrefix("- [ ]") {
                return line
            }

            return "- [ ] \(line)"
        }.joined(separator: "\n")
    }

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty, !haystack.isEmpty else { return 0 }

        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex

        while let range = haystack.range(of: needle, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }

        return count
    }

    private func renderOptimizationPackage(basePrompt: String, output: OptimizationOutput) -> String {
        var sections: [String] = []
        sections.append("### Model Family")
        sections.append(selectedModelFamily.rawValue)
        sections.append("")
        sections.append("### Scenario")
        sections.append(selectedScenarioProfile.rawValue)
        sections.append("")

        if let systemPreamble = output.systemPreamble, !systemPreamble.isEmpty {
            sections.append("### System Preamble")
            sections.append(systemPreamble)
            sections.append("")
        }

        sections.append("### Optimized Prompt")
        sections.append(output.optimizedPrompt)
        sections.append("")
        sections.append("### Suggested Parameters")
        sections.append("- temperature: \(output.suggestedTemperature.map { String(format: "%.2f", $0) } ?? "n/a")")
        sections.append("- top_p: \(output.suggestedTopP.map { String(format: "%.2f", $0) } ?? "n/a")")
        sections.append("- max_tokens: \(output.suggestedMaxTokens.map(String.init) ?? "n/a")")
        sections.append("")
        sections.append("### Applied Rules")
        sections.append(output.appliedRules.isEmpty ? "- None" : bulletize(output.appliedRules))
        sections.append("")
        sections.append("### Warnings")
        sections.append(output.warnings.isEmpty ? "- None" : bulletize(output.warnings))
        sections.append("")
        sections.append("### Legacy Canonical Draft")
        sections.append(basePrompt)

        return sections.joined(separator: "\n")
    }

    private func clearOptimizationMetadata() {
        lastOptimizationOutput = nil
        optimizationAppliedRules = []
        optimizationWarnings = []
        optimizationSystemPreamble = nil
        optimizationSuggestedTemperature = nil
        optimizationSuggestedTopP = nil
        optimizationSuggestedMaxTokens = nil
    }
}
