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

    @Published private(set) var templates: [PromptTemplate] = []
    @Published private(set) var history: [PromptHistoryEntry] = []

    var onRevealStateChanged: ((Bool) -> Void)?

    private let storageManager: StorageManager
    private let variableRegex = try? NSRegularExpression(pattern: #"\{([a-zA-Z0-9_\-]+)\}"#)

    init(storageManager: StorageManager = StorageManager()) {
        self.storageManager = storageManager
        self.templates = storageManager.loadTemplates()
        self.history = storageManager.loadHistory()
    }

    var qualityChecks: [QualityCheck] {
        let currentInput = resolvedInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? roughInput
            : resolvedInput
        let hasGoal = currentInput.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12
        let hasConstraints = options.activeConstraintCount > 0
        let variablesComplete = detectedVariables.allSatisfy {
            !(variableValues[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return [
            QualityCheck(title: "Goal Defined", passed: hasGoal),
            QualityCheck(title: "Constraints Active", passed: hasConstraints),
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
        generatedPrompt = buildPrompt(from: resolvedInput)
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

    func exportForIDE(_ format: IDEExportFormat) {
        guard !generatedPrompt.isEmpty else {
            statusMessage = "Forge a prompt before exporting."
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
            let template = PromptTemplate(name: name, content: roughInput, target: selectedTarget)
            templates.insert(template, at: 0)
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
        let goal = extractGoal(from: input)
        let context = extractContext(from: input)
        let constraints = buildConstraintLines(target: selectedTarget)
        let deliverables = buildDeliverablesLines(target: selectedTarget)

        switch selectedTarget {
        case .claude:
            return buildClaudePrompt(goal: goal, context: context, constraints: constraints, deliverables: deliverables)
        case .agenticIDE:
            return buildAgenticIDEPrompt(goal: goal, context: context, constraints: constraints, deliverables: deliverables)
        case .perplexity:
            return buildPerplexityPrompt(goal: goal, context: context, constraints: constraints, deliverables: deliverables)
        case .geminiChatGPT:
            return buildGeminiChatGPTPrompt(goal: goal, context: context, constraints: constraints, deliverables: deliverables)
        }
    }

    private func extractGoal(from input: String) -> String {
        let lines = input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.first ?? "Define and complete the requested task precisely."
    }

    private func extractContext(from input: String) -> String {
        let lines = input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count <= 1 {
            return input
        }

        return lines.dropFirst().joined(separator: "\n")
    }

    private func buildConstraintLines(target: PromptTarget) -> [String] {
        var lines: [String] = []

        if options.noConversationalFiller {
            lines.append("Respond only with the requested output. Do not apologize or use conversational filler.")
        }
        if options.enforceMarkdown {
            lines.append("Use strict markdown structure and headings exactly as specified.")
        }
        if options.strictCodeOnly {
            lines.append("Output strict code or configuration only when code is requested.")
        }
        if options.addFileTreeRequest {
            lines.append("Include a concrete file tree with exact file paths where relevant.")
        }
        if options.includeVerificationChecklist {
            lines.append("End with a concise verification checklist tied to the requested deliverables.")
        }

        switch target {
        case .perplexity:
            lines.append("Ground claims in verifiable sources and explicitly flag uncertain facts.")
        case .agenticIDE:
            lines.append("Use deterministic, file-writing agent instructions with explicit command execution order.")
        case .claude, .geminiChatGPT:
            break
        }

        return lines
    }

    private func buildDeliverablesLines(target: PromptTarget) -> [String] {
        var lines = [
            "A complete response that satisfies every listed constraint.",
            "Clear assumptions called out before execution details."
        ]

        if options.addFileTreeRequest || target == .agenticIDE {
            lines.append("An explicit file tree request before implementation details.")
        }
        if options.includeVerificationChecklist {
            lines.append("A final verification checklist with pass/fail checkpoints.")
        }
        if target == .perplexity {
            lines.append("Citations for factual claims and a short confidence note.")
        }

        return lines
    }

    private func bulletize(_ lines: [String]) -> String {
        lines.map { "- \($0)" }.joined(separator: "\n")
    }

    private func buildClaudePrompt(goal: String, context: String, constraints: [String], deliverables: [String]) -> String {
        """
        <objective>
        \(goal)
        </objective>

        <context>
        \(context)
        </context>

        <constraints>
        \(bulletize(constraints))
        </constraints>

        <deliverables>
        \(bulletize(deliverables))
        </deliverables>
        """
    }

    private func buildGeminiChatGPTPrompt(goal: String, context: String, constraints: [String], deliverables: [String]) -> String {
        """
        Respond only with the requested output. Do not apologize or use conversational filler.

        ### Goal
        \(goal)

        ### Context
        \(context)

        ### Constraints
        \(bulletize(constraints))

        ### Deliverables
        \(bulletize(deliverables))
        """
    }

    private func buildPerplexityPrompt(goal: String, context: String, constraints: [String], deliverables: [String]) -> String {
        """
        ### Goal
        \(goal)

        ### Context
        \(context)

        ### Constraints
        \(bulletize(constraints))

        ### Deliverables
        \(bulletize(deliverables))

        ### Search & Verification Requirements
        - Cite sources for factual claims.
        - Verify key facts before synthesis.
        - If evidence conflicts, present both positions before concluding.
        - Distinguish facts from assumptions.
        """
    }

    private func buildAgenticIDEPrompt(goal: String, context: String, constraints: [String], deliverables: [String]) -> String {
        let commandHint = "Use reproducible commands and avoid destructive git operations unless explicitly approved."

        return """
        # DexCraft Agentic System Rules

        ## Mission
        \(goal)

        ## Context
        \(context)

        ## Operating Constraints
        \(bulletize(constraints))

        ## Deliverables
        \(bulletize(deliverables))

        ### File Tree Request
        - Propose exact files to create/update before writing code.
        - Include absolute or workspace-relative paths.

        ### Build/Run Commands
        - List commands in execution order.
        - \(commandHint)

        ### Git/Revert Plan
        - Describe commit strategy and rollback path.
        - Do not rewrite history unless asked.

        ### Implementation Style
        - Write deterministic, file-system-aware instructions.
        - Prefer direct edits over speculative alternatives.
        - Include validation steps with expected outcomes.
        """
    }
}
