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
    @Published var selectedScenarioProfile: ScenarioProfile = .generalAssistant
    @Published var autoOptimizePrompt: Bool = true
    @Published var roughInput: String = "" {
        didSet { syncVariables() }
    }
    @Published private(set) var detectedVariables: [String] = []
    @Published var variableValues: [String: String] = [:]
    @Published var options: EnhancementOptions = .init()
    @Published var activeTab: WorkbenchTab = .enhance

    @Published var generatedPrompt: String = ""
    @Published private(set) var finalPrompt: String = ""
    @Published private(set) var debugReport: String = ""
    @Published var resolvedInput: String = ""
    @Published var isResultPanelVisible: Bool = false {
        didSet { onRevealStateChanged?(isResultPanelVisible) }
    }
    @Published var showDiff: Bool = false
    @Published var showDebugReport: Bool = false
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
    @Published private(set) var tinyModelStatus: String = ""

    @Published private(set) var templates: [PromptTemplate] = []
    @Published private(set) var history: [PromptHistoryEntry] = []
    @Published var promptLibrarySearchQuery: String = ""
    @Published var promptLibrarySelectedCategoryId: UUID?
    @Published private(set) var promptLibraryCategories: [PromptCategory] = []
    @Published private(set) var promptLibraryTags: [PromptTag] = []
    @Published private(set) var promptLibraryPrompts: [PromptLibraryItem] = []
    @Published private(set) var connectedModelSettings: ConnectedModelSettings = ConnectedModelSettings()
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
    private let embeddedTinyLLMService = EmbeddedTinyLLMService()
    private let variableRegex: NSRegularExpression = PromptEngineViewModel.compileVariableRegex()
    private var learnedHeuristicWeights: HeuristicScoringWeights?

    private let noFillerConstraint = "Respond only with the requested output. Do not apologize or use conversational filler."
    private let markdownConstraint = "Use strict markdown structure and headings exactly as specified."
    private let strictCodeConstraint = "Output strict code or configuration only when code is requested."
    private let ambiguityLexicon: Set<String> = [
        "maybe", "possibly", "perhaps", "some", "various", "several",
        "generally", "roughly", "approximately", "kind", "stuff",
        "things", "probably", "might", "could", "etc"
    ]
    private let semanticStopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "your", "you", "are", "was", "were",
        "have", "has", "had", "will", "would", "should", "could", "can", "not", "only", "just", "then",
        "task", "request", "prompt", "rewrite", "rewritten", "response", "output", "outputs", "goal",
        "goals", "context", "constraint", "constraints", "deliverable", "deliverables", "validation",
        "checks", "check", "requirement", "requirements", "behavior", "functional", "implementation",
        "implement", "assistant", "section", "sections"
    ]

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

    private enum RewriteMode: String {
        case minimal
        case standard
        case aggressive
    }

    private enum IRSectionKey {
        case goalOrTask
        case context
        case constraints
        case deliverables
    }

    private enum PromptIntent {
        case creativeStory
        case gameDesign
        case softwareBuild
        case general
    }

    private struct PromptIR {
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

    private struct ValidationMetrics {
        let complianceScore: Double
        let ambiguityIndex: Double?
        let templateOverlap: Double?
    }

    private struct ValidationResult {
        let isValid: Bool
        let errors: [String]
        let warnings: [String]
        let metrics: ValidationMetrics
    }

    init(
        storageManager: StorageManager = StorageManager(),
        promptLibraryRepository: PromptLibraryRepository = PromptLibraryRepository()
    ) {
        self.storageManager = storageManager
        self.promptLibraryRepository = promptLibraryRepository
        connectedModelSettings = storageManager.loadConnectedModelSettings()
        if connectedModelSettings.useEmbeddedTinyModel == nil {
            connectedModelSettings.useEmbeddedTinyModel = true
        }
        if (connectedModelSettings.embeddedTinyModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            connectedModelSettings.embeddedTinyModelIdentifier = ConnectedModelSettings.defaultTinyModelIdentifier
        }
        if connectedModelSettings.isEmbeddedTinyModelEnabled {
            selectedModelFamily = .localCLIRuntimes
        }
        storageManager.saveConnectedModelSettings(connectedModelSettings)
        templates = storageManager.loadTemplates()
        history = storageManager.loadHistory()
        learnedHeuristicWeights = storageManager.loadOptimizerWeights()

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

    func updateConnectedModelSettings(_ settings: ConnectedModelSettings) {
        connectedModelSettings = settings
        storageManager.saveConnectedModelSettings(settings)
    }

    var isEmbeddedTinyModelEnabled: Bool {
        connectedModelSettings.isEmbeddedTinyModelEnabled
    }

    var embeddedTinyModelPath: String {
        connectedModelSettings.resolvedTinyModelPath ?? ""
    }

    var embeddedTinyModelIdentifier: String {
        connectedModelSettings.resolvedTinyModelIdentifier
    }

    func setEmbeddedTinyModelEnabled(_ enabled: Bool) {
        var updated = connectedModelSettings
        updated.useEmbeddedTinyModel = enabled
        if enabled {
            autoOptimizePrompt = true
            selectedModelFamily = .localCLIRuntimes
            if (updated.embeddedTinyModelIdentifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.embeddedTinyModelIdentifier = ConnectedModelSettings.defaultTinyModelIdentifier
            }
        }
        updateConnectedModelSettings(updated)
    }

    func toggleEmbeddedTinyModelEnabled() {
        setEmbeddedTinyModelEnabled(!isEmbeddedTinyModelEnabled)
    }

    func updateEmbeddedTinyModelPath(_ path: String) {
        var updated = connectedModelSettings
        updated.embeddedTinyModelPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        updateConnectedModelSettings(updated)
    }

    func browseEmbeddedTinyModelPath() {
        let panel = NSOpenPanel()
        panel.title = "Select SmolLM2 GGUF Model"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            if let ggufType = UTType(filenameExtension: "gguf") {
                panel.allowedContentTypes = [ggufType]
            }
        } else {
            panel.allowedFileTypes = ["gguf"]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateEmbeddedTinyModelPath(url.path)
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

        let hasClaudeXMLTags = selectedTarget != .claude ||
            generatedPrompt.contains(heading("Task")) ||
            generatedPrompt.contains(heading("Goal"))
        let hasAgenticBuildRun = selectedTarget != .agenticIDE || generatedPrompt.contains(heading("Proposed File Changes"))
        let hasAgenticGitRevert = selectedTarget != .agenticIDE || generatedPrompt.contains(heading("Validation Commands"))
        let sectionOrderValid = hasRequiredSectionOrder(in: generatedPrompt)

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

        if connectedModelSettings.isEmbeddedTinyModelEnabled && selectedModelFamily != .localCLIRuntimes {
            selectedModelFamily = .localCLIRuntimes
        }

        let parsed = parseInputSections(from: resolvedInput)
        let canonical = buildCanonicalPrompt(from: parsed, target: selectedTarget)
        let mode = resolveRewriteMode(autoOptimize: autoOptimizePrompt, options: options)
        let initialIR = parseRawInputToIR(
            rawInput: resolvedInput,
            target: selectedTarget,
            mode: mode,
            options: options
        )
        var selectedIR = initialIR
        var fallbackNotes: [String] = ["Initial rewrite mode: \(mode.rawValue)"]
        var compiledFinalPrompt = compileFinalPrompt(from: initialIR)
        var validation = validate(finalPrompt: compiledFinalPrompt, ir: initialIR, options: options)

        if !validation.isValid, mode != .minimal {
            fallbackNotes.append("Validation failed in \(mode.rawValue); retrying with minimal mode.")
            let minimalIR = parseRawInputToIR(
                rawInput: resolvedInput,
                target: selectedTarget,
                mode: .minimal,
                options: options
            )
            let minimalPrompt = compileFinalPrompt(from: minimalIR)
            let minimalValidation = validate(finalPrompt: minimalPrompt, ir: minimalIR, options: options)

            selectedIR = minimalIR
            compiledFinalPrompt = minimalPrompt
            validation = minimalValidation
            fallbackNotes.append("Minimal mode validation: \(minimalValidation.isValid ? "passed" : "failed").")
        }

        if !validation.isValid {
            fallbackNotes.append("Validation still failing; falling back to raw input.")
            compiledFinalPrompt = resolvedInput.trimmingCharacters(in: .whitespacesAndNewlines)
            selectedIR = PromptIR(
                rawInput: resolvedInput.trimmingCharacters(in: .whitespacesAndNewlines),
                target: selectedTarget,
                mode: .minimal,
                goalOrTask: resolvedInput.trimmingCharacters(in: .whitespacesAndNewlines),
                context: nil,
                constraints: [],
                deliverables: [],
                outputContract: outputContractLines(
                    for: selectedTarget,
                    mode: .minimal,
                    options: options,
                    intent: inferPromptIntent(from: resolvedInput)
                ),
                debugNotes: ["Last-resort fallback to raw input after validation failure."]
            )
        }

        let baselinePrompt = shouldUseRawBaselineForHeuristicOptimization(
            rawInput: resolvedInput,
            compiledPrompt: compiledFinalPrompt
        ) ? resolvedInput.trimmingCharacters(in: .whitespacesAndNewlines) : compiledFinalPrompt
        var selectedFinalPrompt = baselinePrompt
        var heuristicResult: HeuristicOptimizationResult?

        if autoOptimizePrompt {
            let context = HeuristicOptimizationContext(
                target: selectedTarget,
                scenario: selectedScenarioProfile,
                historyPrompts: history.map(\.generatedPrompt),
                localWeights: learnedHeuristicWeights
            )
            let result = HeuristicPromptOptimizer.optimize(baselinePrompt, context: context)
            heuristicResult = result
            let trimmedOptimized = result.optimizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOptimized.isEmpty {
                selectedFinalPrompt = baselinePrompt
            } else {
                let taskIntent = inferPromptIntent(from: selectedIR.goalOrTask)
                let enforceAlignment = taskIntent == .softwareBuild || taskIntent == .gameDesign
                let coverage = semanticAnchorCoverage(
                    candidate: trimmedOptimized,
                    baselineTask: selectedIR.goalOrTask
                )

                if enforceAlignment && coverage < 0.30 {
                    selectedFinalPrompt = baselinePrompt
                    fallbackNotes.append(
                        String(
                            format: "Heuristic candidate rejected for low task alignment (coverage %.2f); baseline retained.",
                            coverage
                        )
                    )
                } else {
                    selectedFinalPrompt = trimmedOptimized
                }
            }
            fallbackNotes.append("Heuristic optimizer selected: \(result.selectedCandidateTitle) (score \(result.score)).")
            if let tuned = result.tunedWeights {
                learnedHeuristicWeights = tuned
                storageManager.saveOptimizerWeights(tuned)
            }
            if !result.breakdown.isEmpty {
                let summary = result.breakdown
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                fallbackNotes.append("Heuristic score breakdown: \(summary)")
            }
            if !result.warnings.isEmpty {
                fallbackNotes.append(contentsOf: result.warnings.map { "Heuristic warning: \($0)" })
            }
        }

        if autoOptimizePrompt && connectedModelSettings.isEmbeddedTinyModelEnabled {
            let tokensHint = max(128, min(900, baselinePrompt.count / 3))
            let request = EmbeddedTinyModelRequest(
                prompt: selectedFinalPrompt,
                scenario: selectedScenarioProfile,
                maxTokens: tokensHint
            )

            do {
                let tinyResult = try embeddedTinyLLMService.rewrite(
                    request: request,
                    settings: connectedModelSettings
                )
                let tinyOutput = tinyResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tinyOutput.isEmpty {
                    let tinyEvaluation = evaluateTinyModelCandidate(
                        candidate: tinyOutput,
                        baselinePrompt: selectedFinalPrompt,
                        ir: selectedIR,
                        options: options
                    )
                    if tinyEvaluation.accepted {
                        selectedFinalPrompt = tinyEvaluation.sanitizedOutput
                        tinyModelStatus = "Tiny model pass applied (\(tinyResult.durationMs)ms)"
                        fallbackNotes.append("Embedded tiny model selected output (\(tinyResult.durationMs)ms).")
                        fallbackNotes.append("Tiny runtime: \(tinyResult.runtimePath)")
                        if !tinyEvaluation.notes.isEmpty {
                            fallbackNotes.append(contentsOf: tinyEvaluation.notes.map { "Tiny note: \($0)" })
                        }
                    } else {
                        tinyModelStatus = "Tiny model output failed validation. Kept heuristic result."
                        fallbackNotes.append("Tiny model output failed validation; heuristic result kept.")
                        if !tinyEvaluation.notes.isEmpty {
                            fallbackNotes.append("Tiny validation errors: \(tinyEvaluation.notes.joined(separator: " | "))")
                        }
                        statusMessage = tinyModelStatus
                    }
                } else {
                    tinyModelStatus = "Tiny model returned empty output. Kept heuristic result."
                    fallbackNotes.append("Tiny model returned empty output; heuristic result kept.")
                    statusMessage = tinyModelStatus
                }
            } catch {
                tinyModelStatus = "Tiny model unavailable: \(error.localizedDescription)"
                fallbackNotes.append("Tiny model unavailable; heuristic result kept.")
                fallbackNotes.append("Tiny model error: \(error.localizedDescription)")
                statusMessage = tinyModelStatus
            }
        } else {
            tinyModelStatus = ""
        }

        finalPrompt = selectedFinalPrompt
        generatedPrompt = selectedFinalPrompt

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
            if let heuristicResult {
                optimizationAppliedRules = ["Heuristic selection: \(heuristicResult.selectedCandidateTitle)"]
                    + output.appliedRules
                optimizationWarnings = heuristicResult.warnings + output.warnings
            } else {
                optimizationAppliedRules = output.appliedRules
                optimizationWarnings = output.warnings
            }
            if !tinyModelStatus.isEmpty {
                optimizationAppliedRules.insert("Embedded tiny model rewrite enabled (\(embeddedTinyModelIdentifier)).", at: 0)
                if tinyModelStatus.localizedCaseInsensitiveContains("unavailable") ||
                    tinyModelStatus.localizedCaseInsensitiveContains("empty") {
                    optimizationWarnings.append(tinyModelStatus)
                } else {
                    optimizationAppliedRules.insert(tinyModelStatus, at: 1)
                }
            }
            optimizationSystemPreamble = output.systemPreamble
            optimizationSuggestedTemperature = output.suggestedTemperature
            optimizationSuggestedTopP = output.suggestedTopP
            optimizationSuggestedMaxTokens = output.suggestedMaxTokens
            debugReport = renderDebugReport(
                ir: selectedIR,
                optimizationOutput: output,
                finalPrompt: selectedFinalPrompt,
                validationResult: validation,
                fallbackNotes: fallbackNotes
            )
        } else {
            clearOptimizationMetadata()
            debugReport = renderDebugReport(
                ir: selectedIR,
                optimizationOutput: nil,
                finalPrompt: selectedFinalPrompt,
                validationResult: validation,
                fallbackNotes: fallbackNotes
            )
        }

        lastCanonicalPrompt = canonical
        isResultPanelVisible = true

        let entry = PromptHistoryEntry(
            target: selectedTarget,
            originalInput: roughInput,
            generatedPrompt: finalPrompt,
            options: options,
            variables: variableValues
        )

        history.insert(entry, at: 0)
        history = Array(history.prefix(50))
        storageManager.saveHistory(history)
        if let tuned = HeuristicPromptOptimizer.learnWeights(from: history.map(\.generatedPrompt)) {
            learnedHeuristicWeights = tuned
            storageManager.saveOptimizerWeights(tuned)
        }
    }

    func copyToClipboard() {
        let clipboardText = userVisiblePrompt
        guard !clipboardText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(clipboardText, forType: .string)
        statusMessage = "Prompt copied to clipboard."
    }

    func exportOptimizedPromptAsMarkdown() {
        let exportText = userVisiblePrompt
        guard !exportText.isEmpty else {
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
                try exportText.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Exported: \(url.path)"
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportForIDE(_ format: IDEExportFormat) {
        let exportText = userVisiblePrompt
        guard !exportText.isEmpty else {
            statusMessage = "Forge a prompt before exporting."
            return
        }

        if options.addFileTreeRequest,
           !userVisiblePrompt.contains(heading("File Tree Request (Before Implementation Details)")) &&
           !userVisiblePrompt.contains(heading("Proposed File Changes")) {
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
                try exportText.write(to: url, atomically: true, encoding: .utf8)
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
        let trimmedStoredPrompt = entry.generatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let restoredFinalPrompt = extractUserFacingPrompt(from: trimmedStoredPrompt)
        finalPrompt = restoredFinalPrompt
        generatedPrompt = restoredFinalPrompt
        debugReport = restoredFinalPrompt == trimmedStoredPrompt ? "" : trimmedStoredPrompt

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
        let enhanced = userVisiblePrompt
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

    var userVisiblePrompt: String {
        if !finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return finalPrompt
        }
        return extractUserFacingPrompt(from: generatedPrompt)
    }

    private func refreshPromptLibraryState() {
        promptLibraryCategories = promptLibraryRepository.categories
        promptLibraryTags = promptLibraryRepository.tags
        promptLibraryPrompts = promptLibraryRepository.prompts
    }

    private static func compileVariableRegex() -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: #"\{([a-zA-Z0-9_\-]+)\}"#)
        } catch {
            NSLog("DexCraft: variable regex compilation failed: \(error.localizedDescription)")
            do {
                return try NSRegularExpression(pattern: "(?!)")
            } catch {
                fatalError("DexCraft: failed to compile match-nothing regex fallback: \(error.localizedDescription)")
            }
        }
    }

    private func parseStructuredList(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncVariables() {
        let nsRange = NSRange(roughInput.startIndex..<roughInput.endIndex, in: roughInput)
        let matches = variableRegex.matches(in: roughInput, options: [], range: nsRange)

        var ordered: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: roughInput)
            else { continue }

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

    private func buildPrompt(from input: String) -> String {
        let mode = resolveRewriteMode(autoOptimize: autoOptimizePrompt, options: options)
        let ir = parseRawInputToIR(rawInput: input, target: selectedTarget, mode: mode, options: options)
        return compileFinalPrompt(from: ir)
    }

    private func shouldUseRawBaselineForHeuristicOptimization(rawInput: String, compiledPrompt: String) -> Bool {
        guard autoOptimizePrompt else { return false }

        let trimmedRaw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCompiled = compiledPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty, !trimmedCompiled.isEmpty else { return false }

        let intent = inferPromptIntent(from: trimmedRaw)
        let supportsRawBaseline: Bool
        switch selectedScenarioProfile {
        case .generalAssistant, .longformWriting:
            supportsRawBaseline = intent != .softwareBuild
        case .ideCodingAssistant:
            supportsRawBaseline = intent == .general
        case .cliAssistant:
            supportsRawBaseline = false
        default:
            supportsRawBaseline = false
        }
        guard supportsRawBaseline else { return false }

        let hasExplicitStructuredSections = hasExplicitCoreHeadings(in: trimmedRaw)

        if hasExplicitStructuredSections {
            return false
        }

        let lowered = trimmedRaw.lowercased()
        let asksForStrictStructure =
            lowered.contains("output format") ||
            lowered.contains("output contract") ||
            lowered.contains("use sections") ||
            lowered.contains("markdown headings") ||
            lowered.contains("json")

        return !asksForStrictStructure
    }

    private func hasExplicitCoreHeadings(in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let heading = detectHeading(in: line) else { continue }
            if [.goal, .context, .constraints, .deliverables].contains(heading.key) {
                return true
            }
        }
        return false
    }

    private func resolveRewriteMode(autoOptimize: Bool, options: EnhancementOptions) -> RewriteMode {
        if options.includeValidationSteps || options.includeRevertPlan || options.includeVerificationChecklist {
            return .aggressive
        }

        if autoOptimize || options.enforceMarkdown || options.strictCodeOnly || options.noConversationalFiller {
            return .standard
        }

        return .minimal
    }

    private func parseRawInputToIR(
        rawInput: String,
        target: PromptTarget,
        mode: RewriteMode,
        options: EnhancementOptions
    ) -> PromptIR {
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
        let extractedDeliverables: [String]
        let extractedConstraints: [String]

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

        let dedupedConstraints = dedupeCaseInsensitiveExact(extractedConstraints)
        let dedupedDeliverables = dedupeCaseInsensitiveExact(extractedDeliverables)

        if dedupedConstraints.count != extractedConstraints.count {
            debugNotes.append("Deduplicated repeated constraints (case-insensitive exact match).")
        }
        if dedupedDeliverables.count != extractedDeliverables.count {
            debugNotes.append("Deduplicated repeated deliverables (case-insensitive exact match).")
        }

        let intent = inferPromptIntent(from: goalOrTask)
        let resolvedDeliverables = dedupedDeliverables.isEmpty
            ? seededDeliverables(for: intent, taskText: goalOrTask)
            : dedupedDeliverables

        let outputContract = outputContractLines(for: target, mode: mode, options: options, intent: intent)
        debugNotes.append("Compiled target-aware output contract for \(target.rawValue).")
        debugNotes.append("Detected intent: \(String(describing: intent)).")

        return PromptIR(
            rawInput: trimmedInput,
            target: target,
            mode: mode,
            goalOrTask: goalOrTask,
            context: context,
            constraints: dedupedConstraints,
            deliverables: resolvedDeliverables,
            outputContract: outputContract,
            debugNotes: debugNotes
        )
    }

    private func detectIRHeading(in line: String) -> (key: IRSectionKey, inlineValue: String)? {
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

    private func extractConstraintLines(from lines: [String]) -> [String] {
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

    private func dedupeCaseInsensitiveExact(_ lines: [String]) -> [String] {
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

    private func outputContractLines(
        for target: PromptTarget,
        mode: RewriteMode,
        options: EnhancementOptions,
        intent: PromptIntent
    ) -> [String] {
        var lines: [String]

        if target != .agenticIDE {
            if selectedScenarioProfile == .cliAssistant {
                lines = [
                    "Return shell commands only unless explanation is explicitly requested.",
                    "Commands must be copy/paste runnable and deterministic.",
                    "Use at most one shell comment line when a note is unavoidable."
                ]
            } else if selectedScenarioProfile == .ideCodingAssistant {
                lines = [
                    "Use sections in this order: Goal, Plan, Deliverables, Validation.",
                    "Plan must name concrete UI/behavior changes and affected files/components.",
                    "Validation must include deterministic checks for each major change."
                ]
            } else {
                switch intent {
                case .creativeStory:
                    lines = [
                        "Use sections in this order: Title, Story.",
                        "Story should include a clear beginning, middle, and ending.",
                        "Keep narrative voice, tense, and point of view consistent."
                    ]
                case .gameDesign:
                    lines = [
                        "Use sections in this order: Concept, Rules, Visual Theme, Interaction Flow.",
                        "Define deterministic turn order and win/draw conditions.",
                        "Explain how thematic marks map to board state."
                    ]
                case .softwareBuild:
                    lines = [
                        "Use sections in this order: Goal, Requirements, Constraints, Deliverables, Validation.",
                        "Requirements must state concrete behavior and user-visible outcomes.",
                        "Validation must map each requirement to a deterministic check."
                    ]
                case .general:
                    lines = []
                }
            }

            if !lines.isEmpty {
                if options.noConversationalFiller {
                    lines.append("Avoid conversational filler.")
                }

                switch mode {
                case .minimal:
                    return Array(lines.prefix(1))
                case .standard:
                    return lines
                case .aggressive:
                    lines.append("Keep structure fixed and do not add extra sections.")
                    return lines
                }
            }
        }

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

    private func inferPromptIntent(from text: String) -> PromptIntent {
        let lowered = text.lowercased()
        let tokens = Set(lowered.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })

        if ["story", "narrative", "plot", "poem", "haiku", "sonnet", "lyrics"].contains(where: tokens.contains) ||
            lowered.contains("short story") {
            return .creativeStory
        }

        let hasGameTerm =
            lowered.contains("tic-tac-toe") ||
            lowered.contains("board game") ||
            lowered.contains("x's") ||
            lowered.contains("o's") ||
            ["gameplay", "chess", "game"].contains(where: tokens.contains)
        if hasGameTerm && ["design", "rules", "rule", "mechanic", "theme"].contains(where: tokens.contains) {
            return .gameDesign
        }

        let lookupVerbWords = ["find", "locate", "search", "list", "show", "open", "read", "summarize", "describe", "explain"]
        let buildVerbWords = ["build", "implement", "create", "develop", "fix", "refactor", "patch", "test", "code", "program", "make", "add", "update"]
        let strongSoftwareCueWords = [
            "api", "function", "class", "script", "repository", "code", "swift", "python", "javascript",
            "typescript", "react", "cli", "frontend", "backend", "module", "component", "bug", "compile", "test", "git"
        ]
        let technicalObjectWords = [
            "app", "application", "game", "platformer", "website", "api", "function", "class", "script", "repository",
            "codebase", "cli", "frontend", "backend", "chess", "tic", "tac", "toe", "minecraft", "clone"
        ]
        let hasLookupIntent = lookupVerbWords.contains(where: tokens.contains)
        let mentionsFilesOnly = tokens.contains("file") || tokens.contains("files") || tokens.contains("document") || tokens.contains("documents")
        let hasBuildVerb = buildVerbWords.contains(where: tokens.contains)
        let hasStrongSoftwareCue = strongSoftwareCueWords.contains(where: tokens.contains) ||
            lowered.contains("codebase") ||
            lowered.contains("source code")
        if hasLookupIntent && mentionsFilesOnly && !hasBuildVerb && !hasStrongSoftwareCue {
            return .general
        }

        if hasStrongSoftwareCue ||
            (hasBuildVerb && technicalObjectWords.contains(where: tokens.contains)) {
            return .softwareBuild
        }

        return .general
    }

    private func seededDeliverables(for intent: PromptIntent, taskText: String) -> [String] {
        switch intent {
        case .creativeStory:
            let subject = extractSubjectAfterAbout(in: taskText) ?? "the requested subject"
            let lowered = taskText.lowercased()
            if lowered.contains("poem") || lowered.contains("haiku") || lowered.contains("sonnet") || lowered.contains("lyrics") {
                return [
                    "Write one complete poem about \(subject) with consistent tone and imagery.",
                    "Use deliberate line/stanza structure and maintain voice consistency.",
                    "End with a clear thematic resolution."
                ]
            }
            return [
                "Write one complete story about \(subject) with a clear beginning, middle, and ending.",
                "Provide a title and keep voice and tense consistent.",
                "End with a resolved outcome tied to the main conflict."
            ]
        case .gameDesign:
            return [
                "Define objective, setup, turn order, and deterministic win/draw rules.",
                "Specify exactly how the thematic marks map to board symbols and turns.",
                "Provide at least one example play sequence and one edge-case rule."
            ]
        case .softwareBuild:
            if selectedScenarioProfile == .ideCodingAssistant {
                return [
                    "Define concrete functional requirements and identify affected files/components.",
                    "Specify an ordered implementation plan with deterministic patch scope.",
                    "Provide focused tests and validation steps that confirm behavior and guard regressions."
                ]
            }
            return [
                "Define the core functional requirements and expected user-visible behavior.",
                "Specify implementation constraints and explicit out-of-scope boundaries.",
                "Provide deterministic validation checks for each major requirement."
            ]
        case .general:
            return []
        }
    }

    private func extractSubjectAfterAbout(in text: String) -> String? {
        let lowered = text.lowercased()
        guard let range = lowered.range(of: "about ") else { return nil }
        let subject = text[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        return subject.isEmpty ? nil : subject
    }

    private func compileFinalPrompt(from ir: PromptIR) -> String {
        switch ir.target {
        case .claude, .geminiChatGPT, .perplexity:
            return compileChatStylePrompt(from: ir)
        case .agenticIDE:
            return compileAgenticIDEPrompt(from: ir)
        }
    }

    private func compileChatStylePrompt(from ir: PromptIR) -> String {
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

    private func compileAgenticIDEPrompt(from ir: PromptIR) -> String {
        let constraints = ir.constraints.isEmpty ? ["No explicit constraints provided."] : ir.constraints
        let proposedFileChanges = ir.deliverables.isEmpty ? ["Not specified in input."] : ir.deliverables

        let patchPlan = Array(ir.outputContract.prefix(min(2, ir.outputContract.count)))
        let validationCommands = ir.outputContract.count > 2
            ? Array(ir.outputContract.dropFirst(2))
            : [ir.outputContract.last ?? "Provide runnable validation commands."]

        let sections = [
            section(title: "Goal", body: ir.goalOrTask),
            section(title: "Constraints", body: bulletize(constraints)),
            section(title: "Proposed File Changes", body: bulletize(proposedFileChanges)),
            section(title: "Patch Plan", body: bulletize(patchPlan)),
            section(title: "Validation Commands", body: bulletize(validationCommands))
        ]

        return sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(
        finalPrompt: String,
        ir: PromptIR,
        options: EnhancementOptions
    ) -> ValidationResult {
        _ = options

        var errors: [String] = []
        var warnings: [String] = []

        let scaffoldMarkers = [
            "### Model Family",
            "### Suggested Parameters",
            "### Applied Rules",
            "### Warnings",
            "### Canonical Draft (Reference)",
            "### Legacy Canonical Draft"
        ]
        let leakedMarkers = scaffoldMarkers.filter(finalPrompt.contains)
        if !leakedMarkers.isEmpty {
            errors.append("Scaffold leakage detected: \(leakedMarkers.joined(separator: ", ")).")
        }

        let preamblePhrase = "Respond only with the requested output"
        let preambleCount = countOccurrences(of: preamblePhrase, in: finalPrompt)
        if preambleCount > 1 {
            errors.append("Repeated preamble phrase detected (\(preambleCount)x): '\(preamblePhrase)'.")
        }

        var normalizedSeen = Set<String>()
        var duplicateLines: [String] = []
        for line in finalPrompt.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if isSeparatorOnlyLine(trimmed) { continue }

            let normalized = normalizeLineForDedupe(trimmed)
            if !normalizedSeen.insert(normalized).inserted {
                duplicateLines.append(trimmed)
            }
        }
        if !duplicateLines.isEmpty {
            errors.append("Duplicate normalized lines detected: \(duplicateLines.joined(separator: " | ")).")
        }

        let retainedConstraints = ir.constraints.filter { finalPrompt.contains($0) }
        let complianceScore: Double
        if ir.constraints.isEmpty {
            complianceScore = 1.0
        } else {
            complianceScore = Double(retainedConstraints.count) / Double(ir.constraints.count)
        }
        if complianceScore < 1.0 {
            let missing = ir.constraints.filter { !finalPrompt.contains($0) }
            errors.append("Constraint retention failure; missing constraints: \(missing.joined(separator: " | ")).")
        }

        let templateEchoNeedle = "Use this compact example only to match structure, not to copy content."
        let hasTemplateEcho = finalPrompt.contains(templateEchoNeedle) && finalPrompt.contains("### Suggested Parameters")
        if hasTemplateEcho {
            errors.append("Template echo detected from legacy report artifacts.")
        }

        let ambiguityIndex = computeAmbiguityIndex(for: finalPrompt)
        if ambiguityIndex > 0.15 {
            warnings.append(String(format: "Ambiguity index warning: %.3f (> 0.15).", ambiguityIndex))
        }

        let metrics = ValidationMetrics(
            complianceScore: complianceScore,
            ambiguityIndex: ambiguityIndex,
            templateOverlap: hasTemplateEcho ? 1.0 : 0.0
        )

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            metrics: metrics
        )
    }

    private func evaluateTinyModelCandidate(
        candidate: String,
        baselinePrompt: String,
        ir: PromptIR,
        options: EnhancementOptions
    ) -> (accepted: Bool, sanitizedOutput: String, notes: [String]) {
        var notes: [String] = []
        var working = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !working.isEmpty else {
            return (false, "", ["Tiny model output was empty."])
        }

        let forbiddenHeadings = [
            "### Model Family",
            "### Suggested Parameters",
            "### Applied Rules",
            "### Warnings",
            "### Canonical Draft (Reference)",
            "### Legacy Canonical Draft"
        ]
        let forbiddenTokens = [
            "model family",
            "suggested parameters",
            "applied rules",
            "legacy canonical draft",
            "canonical draft (reference)"
        ]
        if forbiddenHeadings.contains(where: { working.contains($0) }) ||
            forbiddenTokens.contains(where: { working.localizedCaseInsensitiveContains($0) }) {
            return (false, "", ["Tiny model output contained forbidden scaffold headings."])
        }

        let minLength = max(80, baselinePrompt.count / 4)
        if working.count < minLength {
            return (false, "", ["Tiny model output too short to be reliable (\(working.count) chars)."])
        }

        working = dedupePromptLinesPreservingOrder(in: working)

        let missingConstraints = ir.constraints.filter { !working.contains($0) }
        if !missingConstraints.isEmpty {
            notes.append("Re-appended \(missingConstraints.count) missing constraints from baseline.")
            working += "\n\n" + missingConstraints.joined(separator: "\n")
        }

        let hasBoilerplateWrapper = containsTinyBoilerplateWrapper(in: working)
        if hasBoilerplateWrapper {
            notes.append("Tiny output contained wrapper language; skipped direct replacement.")
        }

        let preservesHeadingStructure = preservesBaselineHeadingStructure(
            candidate: working,
            baselinePrompt: baselinePrompt
        )
        if !preservesHeadingStructure {
            notes.append("Tiny output did not preserve section headings; skipped direct replacement.")
        }

        let semanticCoverage = semanticAnchorCoverage(candidate: working, baselineTask: ir.goalOrTask)
        if semanticCoverage < 0.34 {
            notes.append(String(format: "Tiny output semantic coverage too low (%.2f).", semanticCoverage))
        }

        let validation = validate(finalPrompt: working, ir: ir, options: options)
        if validation.isValid && !hasBoilerplateWrapper && preservesHeadingStructure && semanticCoverage >= 0.34 {
            return (true, working, notes)
        }

        if
            let structuredFallback = synthesizeTinyGoalRefinement(
                candidate: working,
                baselinePrompt: baselinePrompt
            )
        {
            let fallbackValidation = validate(finalPrompt: structuredFallback, ir: ir, options: options)
            if fallbackValidation.isValid {
                notes.append("Applied tiny refinement to primary goal/task section while preserving baseline structure.")
                return (true, structuredFallback, notes)
            }
        }

        if
            semanticCoverage >= 0.20,
            let hintFallback = synthesizeTinyHintRefinement(
                candidate: working,
                baselinePrompt: baselinePrompt
            )
        {
            let hintValidation = validate(finalPrompt: hintFallback, ir: ir, options: options)
            if hintValidation.isValid {
                notes.append("Applied tiny hint refinement in goal/task section while preserving baseline structure.")
                return (true, hintFallback, notes)
            }
        }

        let issues = validation.errors + validation.warnings
        return (false, "", issues.isEmpty ? ["Tiny output validation failed."] : issues)
    }

    private func containsTinyBoilerplateWrapper(in text: String) -> Bool {
        let lowered = text.lowercased()
        let wrappers = [
            "here is a rewritten prompt",
            "here's a rewritten prompt",
            "this rewritten prompt",
            "it includes:",
            "meets all constraints",
            "delivers the requested functionality"
        ]
        return wrappers.contains(where: lowered.contains)
    }

    private func preservesBaselineHeadingStructure(
        candidate: String,
        baselinePrompt: String
    ) -> Bool {
        let baselineHeadings = headingLines(in: baselinePrompt)
        guard !baselineHeadings.isEmpty else { return true }

        let candidateHeadings = Set(headingLines(in: candidate))
        return baselineHeadings.allSatisfy(candidateHeadings.contains)
    }

    private func headingLines(in text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.hasPrefix("### ") }
    }

    private func semanticAnchorCoverage(candidate: String, baselineTask: String) -> Double {
        let anchors = Set(semanticAnchorTokens(from: baselineTask))
        guard !anchors.isEmpty else { return 1.0 }

        let candidateTokens = Set(semanticAnchorTokens(from: candidate))
        guard !candidateTokens.isEmpty else { return 0.0 }

        let overlap = anchors.intersection(candidateTokens)
        return Double(overlap.count) / Double(anchors.count)
    }

    private func semanticAnchorTokens(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !semanticStopwords.contains($0) }
    }

    private func synthesizeTinyGoalRefinement(
        candidate: String,
        baselinePrompt: String
    ) -> String? {
        let baselineLines = baselinePrompt.components(separatedBy: .newlines)
        guard !baselineLines.isEmpty else { return nil }

        let headingIndices = baselineLines.indices.filter { idx in
            baselineLines[idx].trimmingCharacters(in: .whitespaces).hasPrefix("### ")
        }
        guard !headingIndices.isEmpty else { return nil }

        guard let preferredGoalIndex = headingIndices.first(where: {
            let heading = baselineLines[$0].trimmingCharacters(in: .whitespaces).lowercased()
            return heading.contains("goal") || heading.contains("task")
        }) else {
            return nil
        }

        let nextHeadingIndex = headingIndices.first(where: { $0 > preferredGoalIndex }) ?? baselineLines.count

        let baselineGoalBody = baselineLines[(preferredGoalIndex + 1)..<nextHeadingIndex]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let candidateCore = extractTinyGoalSentence(
            from: candidate,
            baselineGoal: baselineGoalBody
        )
        guard !candidateCore.isEmpty else { return nil }

        var merged = Array(baselineLines[0...preferredGoalIndex])
        merged.append(candidateCore)
        if nextHeadingIndex < baselineLines.count {
            merged.append(contentsOf: baselineLines[nextHeadingIndex...])
        }

        return merged.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func synthesizeTinyHintRefinement(
        candidate: String,
        baselinePrompt: String
    ) -> String? {
        let hints = extractTinyHints(from: candidate)
        guard !hints.isEmpty else { return nil }

        let baselineLines = baselinePrompt.components(separatedBy: .newlines)
        let headingIndices = baselineLines.indices.filter { idx in
            baselineLines[idx].trimmingCharacters(in: .whitespaces).hasPrefix("### ")
        }
        guard
            let goalHeadingIndex = headingIndices.first(where: {
                let heading = baselineLines[$0].trimmingCharacters(in: .whitespaces).lowercased()
                return heading.contains("goal") || heading.contains("task")
            })
        else {
            return nil
        }

        let nextHeadingIndex = headingIndices.first(where: { $0 > goalHeadingIndex }) ?? baselineLines.count
        let baselineGoalBodyLines = baselineLines[(goalHeadingIndex + 1)..<nextHeadingIndex]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !baselineGoalBodyLines.isEmpty else { return nil }

        let baselineGoalBody = baselineGoalBodyLines.joined(separator: " ")
        let hintClause = hints.prefix(2).joined(separator: " and ")
        let refinedGoalBody: String
        if baselineGoalBody.localizedCaseInsensitiveContains(hintClause) {
            refinedGoalBody = baselineGoalBody
        } else {
            refinedGoalBody = "\(baselineGoalBody) Emphasize \(hintClause)."
        }

        var merged = Array(baselineLines[0...goalHeadingIndex])
        merged.append(refinedGoalBody)
        if nextHeadingIndex < baselineLines.count {
            merged.append(contentsOf: baselineLines[nextHeadingIndex...])
        }

        return merged.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTinyHints(from candidate: String) -> [String] {
        let hintLexicon: [String: String] = [
            "rule": "explicit rules",
            "rules": "explicit rules",
            "output": "explicit outputs",
            "outputs": "explicit outputs",
            "check": "completion checks",
            "checks": "completion checks",
            "test": "testability",
            "tests": "testability",
            "deterministic": "determinism",
            "constraint": "constraints",
            "constraints": "constraints",
            "deliverable": "deliverables",
            "deliverables": "deliverables"
        ]

        var orderedHints: [String] = []
        let tokens = candidate
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for token in tokens {
            guard let mapped = hintLexicon[token] else { continue }
            if !orderedHints.contains(mapped) {
                orderedHints.append(mapped)
            }
            if orderedHints.count >= 3 {
                break
            }
        }

        return orderedHints
    }

    private func extractTinyGoalSentence(from candidate: String, baselineGoal: String) -> String {
        var lines: [String] = []
        for rawLine in candidate.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                if !lines.isEmpty { break }
                continue
            }
            if trimmed == "```" || trimmed.hasPrefix("```") {
                continue
            }
            if trimmed.hasPrefix("#") {
                continue
            }
            let lowered = trimmed.lowercased()
            if lowered.contains("rewritten prompt") ||
                lowered.contains("model family") ||
                lowered.contains("suggested parameters") ||
                lowered.contains("applied rules") ||
                lowered.contains("legacy canonical draft") ||
                lowered.contains("import ") ||
                lowered.contains("def ") ||
                lowered.contains("print(") ||
                lowered.contains("{") ||
                lowered.contains("}") {
                continue
            }

            let cleaned = trimmed
                .replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                lines.append(cleaned)
            }

            if lines.joined(separator: " ").count >= 180 {
                break
            }
        }

        let sentence = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return "" }

        let overlap = lexicalOverlapScore(sentence, baselineGoal)
        return overlap >= 0.20 ? sentence : ""
    }

    private func lexicalOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(tokenizeForOverlap(lhs))
        let rhsTokens = Set(tokenizeForOverlap(rhs))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0.0 }

        let intersection = lhsTokens.intersection(rhsTokens)
        return Double(intersection.count) / Double(rhsTokens.count)
    }

    private func tokenizeForOverlap(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
    }

    private func dedupePromptLinesPreservingOrder(in text: String) -> String {
        var seen = Set<String>()
        var lines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                lines.append(line)
                continue
            }

            if isSeparatorOnlyLine(trimmed) {
                lines.append(line)
                continue
            }

            let key = normalizeLineForDedupe(trimmed)
            if seen.insert(key).inserted {
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func computeAmbiguityIndex(for text: String) -> Double {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return 0.0 }
        let vagueTokenCount = tokens.filter { ambiguityLexicon.contains($0) }.count
        return Double(vagueTokenCount) / Double(tokens.count)
    }

    private func isSeparatorOnlyLine(_ line: String) -> Bool {
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

    private func renderDebugReport(
        ir: PromptIR,
        optimizationOutput: OptimizationOutput?,
        finalPrompt: String,
        validationResult: ValidationResult,
        fallbackNotes: [String]
    ) -> String {
        var sections: [String] = []

        if let optimizationOutput {
            sections.append(renderOptimizationPackage(basePrompt: finalPrompt, output: optimizationOutput))
        }

        var debugLines: [String] = []
        debugLines.append("### Rewrite Debug")
        debugLines.append("- mode: \(ir.mode.rawValue)")
        debugLines.append("- target: \(ir.target.rawValue)")
        debugLines.append("- constraints: \(ir.constraints.count)")
        debugLines.append("- deliverables: \(ir.deliverables.count)")
        debugLines.append("- output_contract_lines: \(ir.outputContract.count)")
        debugLines.append("- raw_input_chars: \(ir.rawInput.count)")
        debugLines.append("- final_prompt_chars: \(finalPrompt.count)")
        debugLines.append(String(format: "- compliance_score: %.3f", validationResult.metrics.complianceScore))
        if let ambiguityIndex = validationResult.metrics.ambiguityIndex {
            debugLines.append(String(format: "- ambiguity_index: %.3f", ambiguityIndex))
        }
        if let templateOverlap = validationResult.metrics.templateOverlap {
            debugLines.append(String(format: "- template_overlap: %.3f", templateOverlap))
        }
        debugLines.append("- validation_status: \(validationResult.isValid ? "pass" : "fail")")

        if !fallbackNotes.isEmpty {
            debugLines.append("")
            debugLines.append("### Fallback Path")
            debugLines.append(contentsOf: fallbackNotes.map { "- \($0)" })
        }

        if !ir.debugNotes.isEmpty {
            debugLines.append("")
            debugLines.append("### Parser Notes")
            debugLines.append(contentsOf: ir.debugNotes.map { "- \($0)" })
        }

        if !validationResult.errors.isEmpty {
            debugLines.append("")
            debugLines.append("### Validation Errors")
            debugLines.append(contentsOf: validationResult.errors.map { "- \($0)" })
        }

        if !validationResult.warnings.isEmpty {
            debugLines.append("")
            debugLines.append("### Validation Warnings")
            debugLines.append(contentsOf: validationResult.warnings.map { "- \($0)" })
        }

        sections.append(debugLines.joined(separator: "\n"))
        return sections.joined(separator: "\n\n")
    }

    private func contextForTarget(profile: PromptProfile, baseContext: String, requirements: [String]) -> String {
        guard !requirements.isEmpty else { return baseContext }

        switch profile.formatStyle {
        case .claudeXML, .markdownHeadings, .agenticIDE, .perplexitySearch:
            return baseContext
        }
    }

    private func dedupePreservingOrder(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for line in lines {
            let key = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted { output.append(key) }
        }
        return output
    }

    private func buildConstraintLines(target: PromptTarget) -> [String] {
        dedupePreservingOrder(optionConstraintLines() + targetConstraintLines(for: target))
    }

    private func buildDeliverablesLines(target: PromptTarget) -> [String] {
        switch target {
        case .claude, .geminiChatGPT, .perplexity, .agenticIDE:
            return [
                "Complete every requested deliverable with concrete output.",
                "Call out assumptions before implementation details."
            ]
        }
    }

    private func buildClaudePrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile
    ) -> String {
        var sections: [String] = []

        sections.append("<provider>\(profile.provider)</provider>")
        sections.append("<connected_model>\(connectedModelLabel(for: profile))</connected_model>")
        sections.append("<system_preamble>\n\(bulletize(profile.defaultSystemPreambleLines))\n</system_preamble>")
        sections.append("<objective>\n\(goal)\n</objective>")
        sections.append("<context>\n\(context.isEmpty ? "No additional context provided." : context)\n</context>")

        if !requirements.isEmpty {
            sections.append("<requirements>\n\(bulletize(requirements))\n</requirements>")
        }

        sections.append("<constraints>\n\(bulletize(constraints))\n</constraints>")
        sections.append("<deliverables>\n\(bulletize(deliverables))\n</deliverables>")
        sections.append("<output_contract>\n\(bulletize(profile.outputContractLines))\n</output_contract>")
        sections.append("<pitfalls_to_avoid>\n\(bulletize(profile.pitfallsAvoidLines))\n</pitfalls_to_avoid>")
        sections.append("<tactics>\n\(bulletize(profile.tacticsLines))\n</tactics>")

        return sections.joined(separator: "\n\n")
    }

    private func buildAgenticIDEPrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile
    ) -> String {
        var sections: [String] = []

        sections.append(section(title: "Provider", body: profile.provider))
        sections.append(section(title: "Connected Model", body: connectedModelLabel(for: profile)))
        sections.append(section(title: "System Preamble", body: bulletize(profile.defaultSystemPreambleLines)))
        sections.append(section(title: "Goal", body: goal))
        sections.append(section(title: "Context", body: context.isEmpty ? "No additional context provided." : context))

        if !requirements.isEmpty {
            sections.append(section(title: "Requirements", body: bulletize(requirements)))
        }

        sections.append(section(title: "Constraints", body: bulletize(constraints)))
        sections.append(section(title: "Deliverables", body: bulletize(deliverables)))
        sections.append(section(title: "Plan", body: bulletize(profile.tacticsLines)))
        sections.append(section(title: "Unified Diff", body: "- Provide a concise, file-scoped unified diff summary."))
        sections.append(section(title: "Tests", body: "- List deterministic test cases and expected outcomes."))
        sections.append(section(title: "Validation", body: bulletize(profile.outputContractLines)))
        sections.append(section(title: "Build/Run Commands", body: "- List commands in execution order."))
        sections.append(section(title: "Git/Revert Plan", body: bulletize(profile.pitfallsAvoidLines)))

        return sections.joined(separator: "\n\n")
    }

    private func buildPerplexityPrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile
    ) -> String {
        var sections: [String] = []

        sections.append(section(title: "Provider", body: profile.provider))
        sections.append(section(title: "Connected Model", body: connectedModelLabel(for: profile)))
        sections.append(section(title: "System Preamble", body: bulletize(profile.defaultSystemPreambleLines)))
        sections.append(section(title: "Goal", body: goal))
        sections.append(section(title: "Context", body: context.isEmpty ? "No additional context provided." : context))

        if !requirements.isEmpty {
            sections.append(section(title: "Requirements", body: bulletize(requirements)))
        }

        sections.append(section(title: "Constraints", body: bulletize(constraints)))
        sections.append(section(title: "Deliverables", body: bulletize(deliverables)))
        sections.append(
            section(
                title: "Search & Verification Requirements",
                body: bulletize([
                    "Search for primary sources before final synthesis.",
                    "Cite sources inline as markdown links for factual claims.",
                    "If evidence conflicts, summarize the conflict and confidence."
                ])
            )
        )
        sections.append(section(title: "Output Contract", body: bulletize(profile.outputContractLines)))
        sections.append(section(title: "Pitfalls to Avoid", body: bulletize(profile.pitfallsAvoidLines)))
        sections.append(section(title: "Tactics", body: bulletize(profile.tacticsLines)))

        return sections.joined(separator: "\n\n")
    }

    private func buildGeminiChatGPTPrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile
    ) -> String {
        var outputContractLines = profile.outputContractLines
        if options.noConversationalFiller {
            outputContractLines.append("Respond only with the requested sections.")
        }

        var sections: [String] = []
        sections.append(section(title: "Provider", body: profile.provider))
        sections.append(section(title: "Connected Model", body: connectedModelLabel(for: profile)))
        sections.append(section(title: "System Preamble", body: bulletize(profile.defaultSystemPreambleLines)))
        sections.append(section(title: "Goal", body: goal))
        sections.append(section(title: "Context", body: context.isEmpty ? "No additional context provided." : context))

        if !requirements.isEmpty {
            sections.append(section(title: "Requirements", body: bulletize(requirements)))
        }

        sections.append(section(title: "Constraints", body: bulletize(constraints)))
        sections.append(section(title: "Deliverables", body: bulletize(deliverables)))
        sections.append(section(title: "Output Contract", body: bulletize(outputContractLines)))
        sections.append(section(title: "Pitfalls to Avoid", body: bulletize(profile.pitfallsAvoidLines)))
        sections.append(section(title: "Tactics", body: bulletize(profile.tacticsLines)))

        return sections.joined(separator: "\n\n")
    }

    private func connectedModelLabel(for profile: PromptProfile) -> String {
        if profile.modelNames.isEmpty {
            return ConnectedModelSettings.unknownUnsetLabel
        }

        return profile.modelNames.joined(separator: ", ")
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
        switch selectedTarget {
        case .agenticIDE:
            return hasOrderedHeadings(
                [
                    heading("Goal"),
                    heading("Constraints"),
                    heading("Proposed File Changes"),
                    heading("Patch Plan"),
                    heading("Validation Commands")
                ],
                in: prompt
            )
        case .claude, .geminiChatGPT, .perplexity:
            var headings: [String] = []
            if prompt.contains(heading("Task")) {
                headings.append(heading("Task"))
            } else if prompt.contains(heading("Goal")) {
                headings.append(heading("Goal"))
            } else {
                return false
            }

            let optionalHeadings = [
                heading("Context"),
                heading("Constraints"),
                heading("Deliverables"),
                heading("Output Contract")
            ]

            for optionalHeading in optionalHeadings where prompt.contains(optionalHeading) {
                headings.append(optionalHeading)
            }

            return hasOrderedHeadings(headings, in: prompt)
        }
    }

    private func hasOrderedHeadings(_ headings: [String], in prompt: String) -> Bool {
        var searchRange = prompt.startIndex..<prompt.endIndex

        for requiredHeading in headings {
            guard let range = prompt.range(of: requiredHeading, options: [], range: searchRange) else {
                return false
            }
            searchRange = range.upperBound..<prompt.endIndex
        }

        return !headings.isEmpty
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
        sections.append("### Canonical Draft (Reference)")
        sections.append(basePrompt)

        return sections.joined(separator: "\n")
    }

    private func extractUserFacingPrompt(from fullText: String) -> String {
        let optimizedHeading = "### Optimized Prompt"
        let canonicalReferenceHeadings = [
            "### Canonical Draft (Reference)",
            "### Legacy Canonical Draft"
        ]
        let stopHeadings = [
            "### Suggested Parameters",
            "### Applied Rules",
            "### Warnings",
            "### Canonical Draft (Reference)",
            "### Legacy Canonical Draft"
        ]

        if let optimizedHeadingRange = fullText.range(of: optimizedHeading) {
            let contentStart = optimizedHeadingRange.upperBound
            let contentTail = fullText[contentStart...]
            var contentEnd = fullText.endIndex

            for stopHeading in stopHeadings {
                if let stopRange = contentTail.range(of: stopHeading), stopRange.lowerBound < contentEnd {
                    contentEnd = stopRange.lowerBound
                }
            }

            return String(fullText[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !fullText.contains(optimizedHeading) {
            for heading in canonicalReferenceHeadings {
                if let headingRange = fullText.range(of: heading) {
                    return String(fullText[headingRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearOptimizationMetadata() {
        lastOptimizationOutput = nil
        optimizationAppliedRules = []
        optimizationWarnings = []
        optimizationSystemPreamble = nil
        optimizationSuggestedTemperature = nil
        optimizationSuggestedTopP = nil
        optimizationSuggestedMaxTokens = nil
        tinyModelStatus = ""
    }
}
