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

struct EmbeddedTinyChatRequest {
    let transcript: String
    let scenario: ScenarioProfile
    let maxTokens: Int
}

enum EmbeddedLocalModelTier: String {
    case tinyPrimary
    case fallbackSecondary

    var statusPrefix: String {
        switch self {
        case .tinyPrimary:
            return "Tiny model"
        case .fallbackSecondary:
            return "Fallback model"
        }
    }
}

struct EmbeddedTinyModelResult {
    let output: String
    let durationMs: Int
    let runtimePath: String
    let modelPath: String
    let tier: EmbeddedLocalModelTier
}

enum EmbeddedTinyModelError: LocalizedError {
    case runtimeNotFound
    case tinyModelNotFound
    case fallbackModelNotFound
    case processFailed(tier: EmbeddedLocalModelTier, exitCode: Int32, detail: String)
    case invalidOutput(tier: EmbeddedLocalModelTier)

    var errorDescription: String? {
        switch self {
        case .runtimeNotFound:
            return "Embedded tiny runtime is missing from DexCraft. Reinstall the app to restore bundled runtime files."
        case .tinyModelNotFound:
            return "Bundled tiny model is missing. Reinstall DexCraft or choose a local .gguf model override in Settings."
        case .fallbackModelNotFound:
            return "Fallback model is unavailable. Add a fallback .gguf path or reinstall DexCraft to restore bundled tiny model."
        case .processFailed(let tier, let exitCode, let detail):
            let cleanedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let condensedDetail = String(cleanedDetail.prefix(320))
            if condensedDetail.isEmpty {
                return "\(tier.statusPrefix) process failed with exit code \(exitCode)."
            }
            return "\(tier.statusPrefix) process failed with exit code \(exitCode): \(condensedDetail)"
        case .invalidOutput(let tier):
            return "\(tier.statusPrefix) produced empty/invalid output."
        }
    }
}

final class EmbeddedTinyLLMService {
    private let fileManager = FileManager.default

    func rewrite(
        request: EmbeddedTinyModelRequest,
        settings: ConnectedModelSettings,
        tier: EmbeddedLocalModelTier = .tinyPrimary
    ) throws -> EmbeddedTinyModelResult {
        try runModel(
            settings: settings,
            tier: tier,
            maxTokens: request.maxTokens,
            systemPrompt: renderSystemPrompt(),
            prompt: renderPrompt(request: request),
            extractor: extractMarkedOutput(from:)
        )
    }

    func chat(
        request: EmbeddedTinyChatRequest,
        settings: ConnectedModelSettings,
        tier: EmbeddedLocalModelTier = .fallbackSecondary
    ) throws -> EmbeddedTinyModelResult {
        try runModel(
            settings: settings,
            tier: tier,
            maxTokens: request.maxTokens,
            systemPrompt: renderChatSystemPrompt(),
            prompt: renderChatPrompt(request: request),
            extractor: extractChatOutput(from:)
        )
    }

    private func runModel(
        settings: ConnectedModelSettings,
        tier: EmbeddedLocalModelTier,
        maxTokens: Int,
        systemPrompt: String,
        prompt: String,
        extractor: (String) -> String
    ) throws -> EmbeddedTinyModelResult {
        let runtimePath = try resolveRuntimePath()
        let runtimeDirectoryPath = (runtimePath as NSString).deletingLastPathComponent
        let modelPath = try resolveModelPath(from: settings, tier: tier)
        let startedAt = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runtimePath)
        process.currentDirectoryURL = URL(fileURLWithPath: runtimeDirectoryPath)
        process.arguments = buildArguments(
            modelPath: modelPath,
            tier: tier,
            requestedMaxTokens: maxTokens,
            systemPrompt: systemPrompt,
            prompt: prompt
        )
        var environment = ProcessInfo.processInfo.environment
        let existingDyldPath = environment["DYLD_LIBRARY_PATH"] ?? ""
        environment["DYLD_LIBRARY_PATH"] = existingDyldPath.isEmpty
            ? runtimeDirectoryPath
            : "\(runtimeDirectoryPath):\(existingDyldPath)"
        process.environment = environment

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
                tier: tier,
                exitCode: process.terminationStatus,
                detail: stderrOutput
            )
        }

        guard !output.isEmpty else {
            throw EmbeddedTinyModelError.invalidOutput(tier: tier)
        }

        let cleaned = extractor(output)
        guard !cleaned.isEmpty else {
            throw EmbeddedTinyModelError.invalidOutput(tier: tier)
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
        return EmbeddedTinyModelResult(
            output: cleaned,
            durationMs: durationMs,
            runtimePath: runtimePath,
            modelPath: modelPath,
            tier: tier
        )
    }

    private func buildArguments(
        modelPath: String,
        tier: EmbeddedLocalModelTier,
        requestedMaxTokens: Int,
        systemPrompt: String,
        prompt: String
    ) -> [String] {
        let generation = generationConfig(for: tier, requestedMaxTokens: requestedMaxTokens)
        return [
            "-m", modelPath,
            "--conversation",
            "--single-turn",
            "--no-warmup",
            "--threads", String(generation.threads),
            "--seed", "7",
            "--system-prompt", systemPrompt,
            "-p", prompt,
            "-n", String(generation.maxTokens),
            "--temp", String(format: "%.2f", generation.temperature),
            "--top-p", String(format: "%.2f", generation.topP),
            "--top-k", String(generation.topK),
            "--repeat-penalty", String(format: "%.2f", generation.repeatPenalty),
            "--ctx-size", String(generation.ctxSize),
            "--simple-io",
            "--no-display-prompt"
        ]
    }

    private func generationConfig(
        for tier: EmbeddedLocalModelTier,
        requestedMaxTokens: Int
    ) -> (
        threads: Int,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        topK: Int,
        repeatPenalty: Double,
        ctxSize: Int
    ) {
        switch tier {
        case .tinyPrimary:
            return (
                threads: 4,
                maxTokens: max(96, min(320, requestedMaxTokens)),
                temperature: 0.20,
                topP: 0.90,
                topK: 40,
                repeatPenalty: 1.05,
                ctxSize: 2048
            )
        case .fallbackSecondary:
            return (
                threads: 4,
                maxTokens: max(128, min(480, requestedMaxTokens)),
                temperature: 0.15,
                topP: 0.88,
                topK: 36,
                repeatPenalty: 1.08,
                ctxSize: 3072
            )
        }
    }

    private func renderSystemPrompt() -> String {
        """
        Rewrite user prompts for execution quality.
        Keep constraints and deliverables intact.
        Return only one rewritten prompt.
        Do not include meta commentary (for example: "Here is a rewritten prompt").
        Do not explain your edits.
        Do not include surrounding quotation marks.
        Preserve existing markdown headings exactly when headings are present.
        """
    }

    private func renderPrompt(request: EmbeddedTinyModelRequest) -> String {
        """
        Scenario: \(request.scenario.rawValue)
        Rewrite the following prompt to be clearer and more executable with minimal edits.
        Preserve all constraints and deliverables.
        Keep headings and section order unchanged when headings exist.
        Do not add or remove sections.
        Return only the rewritten prompt text with no labels, prefaces, explanations, bullets, or titles.

        \(request.prompt)
        """
    }

    private func renderChatSystemPrompt() -> String {
        """
        You are DexCraft's local prompt coach.
        Help the user create stronger prompts with clear scope, constraints, and deliverables.
        Keep responses practical and concise.
        Ask direct clarifying questions when required details are missing.
        """
    }

    private func renderChatPrompt(request: EmbeddedTinyChatRequest) -> String {
        """
        Scenario: \(request.scenario.rawValue)
        Conversation:
        \(request.transcript)

        Respond as Assistant with one concise reply.
        """
    }

    private func extractMarkedOutput(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        if
            let tagged = extractTaggedPrompt(from: normalized),
            !tagged.isEmpty
        {
            return tagged
        }

        if
            let quoted = extractFirstQuotedBlock(from: normalized),
            !quoted.isEmpty
        {
            return quoted
        }

        var lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        while let first = lines.first, isTinyMetaLine(first) {
            lines.removeFirst()
        }

        if let explanationStart = lines.firstIndex(where: isTinyExplanationStart) {
            lines = Array(lines[..<explanationStart])
        }

        let collapsed = lines
            .filter { !$0.isEmpty && $0 != "[end of text]" }
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "" }
        return collapsed
    }

    private func extractTaggedPrompt(from text: String) -> String? {
        guard
            let start = text.range(of: "<prompt>", options: [.caseInsensitive]),
            let end = text.range(of: "</prompt>", options: [.caseInsensitive], range: start.upperBound..<text.endIndex)
        else {
            return nil
        }

        let tagged = text[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tagged.isEmpty ? nil : tagged
    }

    private func extractFirstQuotedBlock(from text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard
            let regex = try? NSRegularExpression(pattern: #""([^"\n]{48,2000})""#, options: []),
            let match = regex.firstMatch(in: text, options: [], range: range),
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        let quoted = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return quoted.isEmpty ? nil : quoted
    }

    private func extractChatOutput(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        if
            let start = normalized.range(of: "<assistant>", options: [.caseInsensitive]),
            let end = normalized.range(
                of: "</assistant>",
                options: [.caseInsensitive],
                range: start.upperBound..<normalized.endIndex
            )
        {
            let tagged = normalized[start.upperBound..<end.lowerBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !tagged.isEmpty {
                return tagged
            }
        }

        var lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "[end of text]" }

        if let first = lines.first {
            let lowered = first.lowercased()
            if lowered.hasPrefix("assistant:") {
                lines[0] = String(first.dropFirst("assistant:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lowered == "assistant" {
                lines.removeFirst()
            }
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTinyMetaLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.isEmpty { return true }
        let markers = [
            "here is a rewritten prompt",
            "here's a rewritten prompt",
            "here’s a rewritten prompt",
            "rewritten prompt:",
            "this is a rewritten prompt",
            "this rewritten prompt",
            "rewrite with minimal edits",
            "scenario:",
            "[end of text]"
        ]
        return markers.contains(where: lowered.contains)
    }

    private func isTinyExplanationStart(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let markers = [
            "i made several changes",
            "changes i made",
            "improvements:",
            "rationale:",
            "why this works"
        ]
        return markers.contains(where: lowered.contains)
    }

    private func resolveRuntimePath() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        if
            let overridePath = environment["DEXCRAFT_EMBEDDED_RUNTIME_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !overridePath.isEmpty,
            fileManager.isExecutableFile(atPath: overridePath)
        {
            return overridePath
        }

        guard
            let runtimeDirectory = Bundle.main.resourceURL?.appendingPathComponent("EmbeddedTinyRuntime", isDirectory: true)
        else {
            throw EmbeddedTinyModelError.runtimeNotFound
        }

        let runtimeExecutable = runtimeDirectory.appendingPathComponent("llama-completion").path
        guard fileManager.isExecutableFile(atPath: runtimeExecutable) else {
            throw EmbeddedTinyModelError.runtimeNotFound
        }

        return runtimeExecutable
    }

    private func resolveModelPath(
        from settings: ConnectedModelSettings,
        tier: EmbeddedLocalModelTier
    ) throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let tinyCandidates = [
            "SmolLM2-135M-Instruct-Q3_K_M.gguf",
            "SmolLM2-135M-Instruct-Q4_K_M.gguf"
        ]
        switch tier {
        case .tinyPrimary:
            if let explicit = settings.resolvedTinyModelPath, fileManager.fileExists(atPath: explicit) {
                return explicit
            }

            if
                let envPath = environment["DEXCRAFT_EMBEDDED_TINY_MODEL_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !envPath.isEmpty,
                fileManager.fileExists(atPath: envPath)
            {
                return envPath
            }

            if
                let bundledTiny = resolveBundledModelPath(candidates: tinyCandidates)
            {
                return bundledTiny
            }

            throw EmbeddedTinyModelError.tinyModelNotFound

        case .fallbackSecondary:
            if let explicit = settings.resolvedFallbackModelPath, fileManager.fileExists(atPath: explicit) {
                return explicit
            }

            if
                let envPath = environment["DEXCRAFT_EMBEDDED_FALLBACK_MODEL_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !envPath.isEmpty,
                fileManager.fileExists(atPath: envPath)
            {
                return envPath
            }

            let bundledFallbackCandidates = [
                "SmolLM2-360M-Instruct-Q4_K_M.gguf",
                "SmolLM2-360M-Instruct-Q3_K_M.gguf",
                "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
                "Qwen2.5-0.5B-Instruct-Q3_K_M.gguf"
            ]
            if let bundledFallback = resolveBundledModelPath(candidates: bundledFallbackCandidates) {
                return bundledFallback
            }

            // If no dedicated fallback model is present, reuse tiny model as best-effort secondary tier.
            if let tinyExplicit = settings.resolvedTinyModelPath, fileManager.fileExists(atPath: tinyExplicit) {
                return tinyExplicit
            }
            if
                let tinyEnvPath = environment["DEXCRAFT_EMBEDDED_TINY_MODEL_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                !tinyEnvPath.isEmpty,
                fileManager.fileExists(atPath: tinyEnvPath)
            {
                return tinyEnvPath
            }
            if let bundledTiny = resolveBundledModelPath(candidates: tinyCandidates) {
                return bundledTiny
            }

            throw EmbeddedTinyModelError.fallbackModelNotFound
        }
    }

    private func resolveBundledModelPath(candidates: [String]) -> String? {
        guard
            let runtimeDirectory = Bundle.main.resourceURL?.appendingPathComponent("EmbeddedTinyRuntime", isDirectory: true)
        else {
            return nil
        }

        for filename in candidates {
            let bundledModelPath = runtimeDirectory.appendingPathComponent(filename).path
            if fileManager.fileExists(atPath: bundledModelPath) {
                return bundledModelPath
            }
        }
        return nil
    }
}
