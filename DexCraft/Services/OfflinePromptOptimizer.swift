import Foundation

final class OfflinePromptOptimizer {
    func optimize(_ input: OptimizationInput) -> OptimizationOutput {
        let behavior = OfflinePromptKnowledgeBase.modelProfiles[input.modelFamily]
            ?? OfflinePromptKnowledgeBase.modelProfiles[.openAIGPTStyle]!
        let scenario = OfflinePromptKnowledgeBase.scenarioRules[input.scenario]
            ?? OfflinePromptKnowledgeBase.scenarioRules[.ideCodingAssistant]!

        let normalizedPrompt = input.rawUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userTask = normalizedPrompt.isEmpty ? "No task text provided." : normalizedPrompt

        var appliedRules: [String] = []
        var warnings: [String] = []

        let strictJSON = input.userOverrides?.strictJSONOverride ?? scenario.strictJsonModePreferred

        var systemLines: [String] = []
        if input.userOverrides?.disableSystemPreamble != true {
            systemLines = baseSystemLines(for: behavior, scenario: scenario)
            if strictJSON {
                systemLines.append("Return output that is machine-parseable and schema-aligned.")
                appliedRules.append("Enabled schema-first strict JSON contract.")
            }
            if behavior.prefersDelimiters {
                systemLines.append("Treat delimited sections as hard boundaries.")
                appliedRules.append("Enabled delimiter-aware prompt framing.")
            }
            if behavior.prefersConciseSystem {
                appliedRules.append("Used concise system preamble style.")
            }
        } else {
            appliedRules.append("Skipped system preamble due to user override.")
        }

        let scenarioInstructions = scenarioInstructionLines(
            scenario: scenario,
            behavior: behavior,
            strictJSON: strictJSON,
            appliedRules: &appliedRules,
            warnings: &warnings
        )

        let fewShot = fewShotBlock(for: scenario, behavior: behavior, appliedRules: &appliedRules)

        let optimizedPrompt = renderOptimizedPrompt(
            scenario: scenario,
            task: userTask,
            scenarioInstructions: scenarioInstructions,
            fewShot: fewShot,
            strictJSON: strictJSON
        )

        let parameters = suggestedParameters(
            scenario: scenario,
            behavior: behavior,
            overrides: input.userOverrides
        )

        if scenario.requiresCitations {
            appliedRules.append("Added citation and uncertainty discipline.")
        }

        if input.modelFamily == .localCLIRuntimes {
            appliedRules.append("Applied Local CLI runtime compression (short prompt, explicit steps, low creativity).")
        }

        if strictJSON && behavior.jsonReliability <= 3 {
            warnings.append("Strict JSON may be brittle for this model family; repair protocol enabled.")
        }

        return OptimizationOutput(
            optimizedPrompt: optimizedPrompt,
            systemPreamble: systemLines.isEmpty ? nil : systemLines.joined(separator: "\n"),
            suggestedTemperature: parameters.temperature,
            suggestedTopP: parameters.topP,
            suggestedMaxTokens: parameters.maxTokens,
            appliedRules: appliedRules,
            warnings: warnings
        )
    }

    private func baseSystemLines(for behavior: ModelBehaviorProfile, scenario: ScenarioRules) -> [String] {
        var lines = [
            "You are an execution-focused assistant.",
            "Follow requested output format exactly.",
            "If uncertain, state uncertainty explicitly instead of guessing."
        ]

        if behavior.reasoningStrength >= 4 {
            lines.append("Prefer explicit assumptions before irreversible actions.")
        }

        if scenario.cliConstraintsEnabled {
            lines.append("Return command-ready output with no conversational filler.")
        }

        return lines
    }

    private func scenarioInstructionLines(
        scenario: ScenarioRules,
        behavior: ModelBehaviorProfile,
        strictJSON: Bool,
        appliedRules: inout [String],
        warnings: inout [String]
    ) -> [String] {
        switch scenario.scenario {
        case .generalAssistant:
            appliedRules.append("Applied general assistant scaffold for chat-style usage.")
            return [
                "Answer directly first, then add concise supporting detail if needed.",
                "Use lightweight structure only when it improves scanability.",
                "State assumptions explicitly before irreversible actions."
            ]
        case .ideCodingAssistant:
            appliedRules.append("Applied IDE coding scaffold (plan + diff + tests + verification).")
            return [
                "Output sections in this order: Plan, Unified Diff, Tests, Validation Commands.",
                "Prefer minimal diff footprint and deterministic file paths.",
                "Write or update tests before final patch summary when feasible."
            ]
        case .cliAssistant:
            appliedRules.append("Applied CLI constraints (commands only, minimal prose).")
            return [
                "Return shell commands only unless the user asks for explanation.",
                "Commands must be copy/paste runnable.",
                "If any note is unavoidable, use a single `#` shell comment line."
            ]
        case .jsonStructuredOutput:
            if strictJSON && behavior.jsonReliability >= 4 {
                appliedRules.append("Applied strict JSON-only output mode.")
                return [
                    "Return JSON only. No markdown, no prose, no code fences.",
                    "Follow the schema exactly and keep key names stable.",
                    "Reject unspecified keys."
                ]
            }

            appliedRules.append("Applied JSON repair protocol fallback.")
            warnings.append("Model family has moderate/low JSON strictness reliability.")
            return [
                "Return JSON only. No markdown or extra text.",
                "Validate JSON before finalizing output.",
                "If first draft is invalid, repair and re-emit valid JSON only."
            ]
        case .longformWriting:
            appliedRules.append("Applied longform continuity and structure constraints.")
            return [
                "Use explicit heading structure and maintain narrative continuity.",
                "Preserve tone consistency across sections.",
                "Mark uncertain facts explicitly to reduce hallucinated claims."
            ]
        case .researchSummarization:
            appliedRules.append("Applied research summary format with confidence labels.")
            return [
                "Separate confirmed facts from tentative claims.",
                "Cite sources inline for factual claims when evidence is provided.",
                "Mark each major claim with confidence: High, Medium, or Low."
            ]
        case .toolUsingAgent:
            if behavior.toolReliability >= 4 {
                appliedRules.append("Applied tool-using agent loop instructions.")
                return [
                    "Use this loop: Plan -> Tool Call -> Observe -> Update Plan -> Final.",
                    "Ask for tool invocation only when required data is missing.",
                    "Keep tool call arguments explicit and minimal."
                ]
            }

            appliedRules.append("Tool calling disabled due to low reliability; using manual fallback.")
            warnings.append("Tool reliability is low for this family; generated manual execution fallback.")
            return [
                "Do not emit tool-call syntax.",
                "Provide a manual step-by-step plan the user can execute directly.",
                "Include checkpoints after each critical step."
            ]
        }
    }

    private func fewShotBlock(
        for scenario: ScenarioRules,
        behavior: ModelBehaviorProfile,
        appliedRules: inout [String]
    ) -> String? {
        switch scenario.scenario {
        case .ideCodingAssistant:
            appliedRules.append("Added compact few-shot for patch-format alignment.")
            return """
            Example format:
            Plan: 1) isolate failing test 2) patch target function.
            Unified Diff: include only touched files and hunks.
            Tests: list exact test names added/updated.
            Validation Commands: provide deterministic command order.
            """
        case .toolUsingAgent where behavior.toolReliability >= 4:
            appliedRules.append("Added compact few-shot for tool-loop alignment.")
            return """
            Example loop:
            Plan -> Tool Call(args) -> Observation -> Next Action -> Final Output
            """
        case .generalAssistant:
            return """
            Example style:
            Direct answer first, followed by short assumptions and optional next steps.
            """
        default:
            return nil
        }
    }

    private func renderOptimizedPrompt(
        scenario: ScenarioRules,
        task: String,
        scenarioInstructions: [String],
        fewShot: String?,
        strictJSON: Bool
    ) -> String {
        var sections: [String] = []
        sections.append("### Scenario")
        sections.append(scenario.scenario.rawValue)
        sections.append("")
        sections.append("### Task")
        sections.append(task)
        sections.append("")
        sections.append("### Output Contract")
        sections.append(scenarioInstructions.map { "- \($0)" }.joined(separator: "\n"))

        if strictJSON && scenario.scenario == .jsonStructuredOutput {
            sections.append("")
            sections.append("### JSON Schema Stub")
            sections.append("""
            {
              "type": "object",
              "properties": {},
              "required": []
            }
            """)
        }

        if let fewShot, !fewShot.isEmpty {
            sections.append("")
            sections.append("### Few-Shot Policy")
            sections.append("Use this compact example only to match structure, not to copy content.")
            sections.append("")
            sections.append(fewShot)
        } else {
            sections.append("")
            sections.append("### Few-Shot Policy")
            sections.append("No few-shot examples included (not beneficial for this scenario/family).")
        }

        return sections.joined(separator: "\n")
    }

    private func suggestedParameters(
        scenario: ScenarioRules,
        behavior: ModelBehaviorProfile,
        overrides: UserOverrideOptions?
    ) -> (temperature: Double?, topP: Double?, maxTokens: Int?) {
        var temperature: Double
        var topP: Double
        var maxTokens: Int

        switch scenario.scenario {
        case .generalAssistant:
            temperature = 0.3
            topP = 0.9
            maxTokens = 1_100
        case .ideCodingAssistant:
            temperature = 0.2
            topP = 0.9
            maxTokens = 1_200
        case .cliAssistant:
            temperature = 0.1
            topP = 0.8
            maxTokens = 500
        case .jsonStructuredOutput:
            temperature = 0.0
            topP = 1.0
            maxTokens = 900
        case .longformWriting:
            temperature = 0.6
            topP = 0.95
            maxTokens = 1_800
        case .researchSummarization:
            temperature = 0.2
            topP = 0.9
            maxTokens = 1_400
        case .toolUsingAgent:
            temperature = 0.2
            topP = 0.9
            maxTokens = 1_300
        }

        if behavior.verbosityBias <= 2 {
            maxTokens = max(400, Int(Double(maxTokens) * 0.75))
        } else if behavior.verbosityBias >= 4 {
            maxTokens = Int(Double(maxTokens) * 1.15)
        }

        if behavior.family == .localCLIRuntimes {
            temperature = min(temperature, 0.2)
            topP = min(topP, 0.85)
            maxTokens = min(maxTokens, 700)
        }

        if let overrideTemperature = overrides?.temperature {
            temperature = overrideTemperature
        }
        if let overrideTopP = overrides?.topP {
            topP = overrideTopP
        }
        if let overrideMaxTokens = overrides?.maxTokens {
            maxTokens = overrideMaxTokens
        }

        return (temperature, topP, maxTokens)
    }
}

struct EmbeddedTinyModelRequest {
    let prompt: String
    let scenario: ScenarioProfile
    let maxTokens: Int
}

struct EmbeddedTinyModelResult {
    let output: String
    let durationMs: Int
    let runtimePath: String
}

enum EmbeddedTinyModelError: LocalizedError {
    case runtimeNotFound
    case modelNotFound
    case processFailed(exitCode: Int32, detail: String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .runtimeNotFound:
            return "Embedded tiny runtime not found. Configure llama.cpp `llama-cli` path in Settings."
        case .modelNotFound:
            return "Tiny model file not found. Configure SmolLM2-135M-Instruct GGUF path in Settings."
        case .processFailed(let exitCode, let detail):
            let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedDetail.isEmpty {
                return "Tiny model process failed with exit code \(exitCode)."
            }
            return "Tiny model process failed with exit code \(exitCode): \(cleanedDetail)"
        case .invalidOutput:
            return "Tiny model produced empty/invalid output."
        }
    }
}

final class EmbeddedTinyLLMService {
    private let fileManager = FileManager.default

    func rewrite(
        request: EmbeddedTinyModelRequest,
        settings: ConnectedModelSettings
    ) throws -> EmbeddedTinyModelResult {
        let runtimePath = try resolveRuntimePath(from: settings)
        let modelPath = try resolveModelPath(from: settings)
        let startedAt = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runtimePath)
        process.arguments = buildArguments(
            request: request,
            modelPath: modelPath
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let group = DispatchGroup()
        var outputData = Data()
        var errorData = Data()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()
        let output = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrOutput = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw EmbeddedTinyModelError.processFailed(
                exitCode: process.terminationStatus,
                detail: stderrOutput
            )
        }

        guard !output.isEmpty else {
            throw EmbeddedTinyModelError.invalidOutput
        }

        let cleaned = extractMarkedOutput(from: output)
        guard !cleaned.isEmpty else {
            throw EmbeddedTinyModelError.invalidOutput
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
        return EmbeddedTinyModelResult(
            output: cleaned,
            durationMs: durationMs,
            runtimePath: runtimePath
        )
    }

    private func buildArguments(
        request: EmbeddedTinyModelRequest,
        modelPath: String
    ) -> [String] {
        let prompt = renderPrompt(request: request)
        return [
            "-m", modelPath,
            "-p", prompt,
            "-n", String(max(64, request.maxTokens)),
            "--temp", "0.2",
            "--top-p", "0.9",
            "--ctx-size", "2048",
            "--simple-io",
            "--no-display-prompt"
        ]
    }

    private func renderPrompt(request: EmbeddedTinyModelRequest) -> String {
        """
        You are DexCraft's embedded tiny prompt optimizer.
        Rewrite the input prompt so it is clearer and more executable.
        Keep all hard constraints and deliverables.
        Preserve existing section structure and heading style when present.
        Do not introduce legacy scaffold/report headings.
        Forbidden headings: ### Model Family, ### Suggested Parameters, ### Applied Rules, ### Warnings, ### Legacy Canonical Draft.
        Output only the rewritten prompt text.
        Never add explanations.

        Scenario: \(request.scenario.rawValue)
        ---
        \(request.prompt)
        ---
        """
    }

    private func extractMarkedOutput(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return ""
        }
        return cleaned
    }

    private func resolveRuntimePath(from settings: ConnectedModelSettings) throws -> String {
        if let explicit = settings.resolvedTinyRuntimePath, fileManager.isExecutableFile(atPath: explicit) {
            return explicit
        }

        if let bundled = Bundle.main.path(forResource: "llama-cli", ofType: nil),
           fileManager.isExecutableFile(atPath: bundled) {
            return bundled
        }

        let candidatePaths = [
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli"
        ]

        if let match = candidatePaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return match
        }

        throw EmbeddedTinyModelError.runtimeNotFound
    }

    private func resolveModelPath(from settings: ConnectedModelSettings) throws -> String {
        if let explicit = settings.resolvedTinyModelPath, fileManager.fileExists(atPath: explicit) {
            return explicit
        }

        if let bundled = Bundle.main.path(forResource: "SmolLM2-135M-Instruct-Q4_K_M", ofType: "gguf"),
           fileManager.fileExists(atPath: bundled) {
            return bundled
        }

        throw EmbeddedTinyModelError.modelNotFound
    }
}
