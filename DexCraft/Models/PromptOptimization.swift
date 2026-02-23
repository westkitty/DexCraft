import Foundation

enum ModelFamily: String, CaseIterable, Codable, Identifiable {
    case openAIGPTStyle = "OpenAI GPT-style (Chat/Tools/JSON)"
    case anthropicClaudeStyle = "Anthropic Claude-style"
    case googleGeminiStyle = "Google Gemini-style"
    case xAIGrokStyle = "xAI Grok-style"
    case metaLlamaFamily = "Meta Llama-family (open-weight)"
    case mistralFamily = "Mistral-family (open + API)"
    case deepSeekFamily = "DeepSeek-family"
    case qwenFamily = "Qwen-family"
    case cohereCommandRerankFamily = "Cohere Command/Rerank-family"
    case localCLIRuntimes = "Local CLI Runtime (Ollama/llama.cpp)"

    var id: String { rawValue }
}

enum ScenarioProfile: String, CaseIterable, Codable, Identifiable {
    case ideCodingAssistant = "IDE Coding Assistant"
    case cliAssistant = "CLI Assistant"
    case jsonStructuredOutput = "JSON / Structured Output"
    case longformWriting = "Longform Writing"
    case researchSummarization = "Research / Summarization"
    case toolUsingAgent = "Tool-Using Agent"

    var id: String { rawValue }
}

enum OutputFormatPolicy: String, Codable {
    case patchAndChecklist
    case shellOnly
    case strictJSON
    case structuredMarkdown
    case citedSummary
    case toolPlanOrManualPlan
}

enum VerbosityPolicy: String, Codable {
    case minimal
    case concise
    case balanced
    case detailed
}

struct UserOverrideOptions: Codable {
    var temperature: Double?
    var topP: Double?
    var maxTokens: Int?
    var strictJSONOverride: Bool?
    var disableSystemPreamble: Bool?

    init(
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        strictJSONOverride: Bool? = nil,
        disableSystemPreamble: Bool? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.strictJSONOverride = strictJSONOverride
        self.disableSystemPreamble = disableSystemPreamble
    }
}

struct ModelBehaviorProfile {
    let family: ModelFamily
    let contextWindowHint: Int?
    let jsonReliability: Int
    let toolReliability: Int
    let verbosityBias: Int
    let reasoningStrength: Int
    let prefersDelimiters: Bool
    let prefersConciseSystem: Bool
    let notes: String
}

struct ScenarioRules {
    let scenario: ScenarioProfile
    let outputFormat: OutputFormatPolicy
    let verbosityTarget: VerbosityPolicy
    let requiresCitations: Bool
    let strictJsonModePreferred: Bool
    let cliConstraintsEnabled: Bool
    let notes: String
}

struct OptimizationInput {
    let rawUserPrompt: String
    let modelFamily: ModelFamily
    let scenario: ScenarioProfile
    let userOverrides: UserOverrideOptions?
}

struct OptimizationOutput {
    let optimizedPrompt: String
    let systemPreamble: String?
    let suggestedTemperature: Double?
    let suggestedTopP: Double?
    let suggestedMaxTokens: Int?
    let appliedRules: [String]
    let warnings: [String]
}

enum OfflinePromptKnowledgeBase {
    // Heuristic scores: these are conservative runtime heuristics, not vendor guarantees.
    static let modelProfiles: [ModelFamily: ModelBehaviorProfile] = [
        .openAIGPTStyle: ModelBehaviorProfile(
            family: .openAIGPTStyle,
            contextWindowHint: 128_000,
            jsonReliability: 5,
            toolReliability: 5,
            verbosityBias: 3,
            reasoningStrength: 5,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Strong structured output/tool usage patterns; concise system directives usually work well."
        ),
        .anthropicClaudeStyle: ModelBehaviorProfile(
            family: .anthropicClaudeStyle,
            contextWindowHint: 200_000,
            jsonReliability: 4,
            toolReliability: 4,
            verbosityBias: 4,
            reasoningStrength: 5,
            prefersDelimiters: true,
            prefersConciseSystem: false,
            notes: "Benefits from explicit structure and clear sectioning; tends to produce rich prose unless constrained."
        ),
        .googleGeminiStyle: ModelBehaviorProfile(
            family: .googleGeminiStyle,
            contextWindowHint: 1_000_000,
            jsonReliability: 4,
            toolReliability: 4,
            verbosityBias: 3,
            reasoningStrength: 4,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Generally reliable with schema-guided output and function-calling prompts."
        ),
        .xAIGrokStyle: ModelBehaviorProfile(
            family: .xAIGrokStyle,
            contextWindowHint: 128_000,
            jsonReliability: 3,
            toolReliability: 3,
            verbosityBias: 3,
            reasoningStrength: 4,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Use explicit schema reminders and fallback validation for strict JSON scenarios."
        ),
        .metaLlamaFamily: ModelBehaviorProfile(
            family: .metaLlamaFamily,
            contextWindowHint: 128_000,
            jsonReliability: 3,
            toolReliability: 2,
            verbosityBias: 3,
            reasoningStrength: 3,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Chat-template fidelity and compact instructions improve consistency."
        ),
        .mistralFamily: ModelBehaviorProfile(
            family: .mistralFamily,
            contextWindowHint: 128_000,
            jsonReliability: 4,
            toolReliability: 4,
            verbosityBias: 3,
            reasoningStrength: 4,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Strong API support for structured outputs and function calling patterns."
        ),
        .deepSeekFamily: ModelBehaviorProfile(
            family: .deepSeekFamily,
            contextWindowHint: 128_000,
            jsonReliability: 3,
            toolReliability: 3,
            verbosityBias: 2,
            reasoningStrength: 4,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Works best with explicit output contracts and deterministic constraints."
        ),
        .qwenFamily: ModelBehaviorProfile(
            family: .qwenFamily,
            contextWindowHint: 128_000,
            jsonReliability: 3,
            toolReliability: 3,
            verbosityBias: 3,
            reasoningStrength: 4,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Prompt length and clearly delimited objectives are important for stability."
        ),
        .cohereCommandRerankFamily: ModelBehaviorProfile(
            family: .cohereCommandRerankFamily,
            contextWindowHint: 128_000,
            jsonReliability: 4,
            toolReliability: 3,
            verbosityBias: 2,
            reasoningStrength: 3,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Command models are concise; rerank/embeddings workflows benefit from explicit field instructions."
        ),
        .localCLIRuntimes: ModelBehaviorProfile(
            family: .localCLIRuntimes,
            contextWindowHint: 32_000,
            jsonReliability: 2,
            toolReliability: 1,
            verbosityBias: 2,
            reasoningStrength: 2,
            prefersDelimiters: true,
            prefersConciseSystem: true,
            notes: "Keep prompts short, direct, and step-wise; avoid heavy control wrappers."
        )
    ]

    static let scenarioRules: [ScenarioProfile: ScenarioRules] = [
        .ideCodingAssistant: ScenarioRules(
            scenario: .ideCodingAssistant,
            outputFormat: .patchAndChecklist,
            verbosityTarget: .balanced,
            requiresCitations: false,
            strictJsonModePreferred: false,
            cliConstraintsEnabled: false,
            notes: "Prefer patch-oriented plans with tests and validation commands."
        ),
        .cliAssistant: ScenarioRules(
            scenario: .cliAssistant,
            outputFormat: .shellOnly,
            verbosityTarget: .minimal,
            requiresCitations: false,
            strictJsonModePreferred: false,
            cliConstraintsEnabled: true,
            notes: "Output should be command-first and copy/paste runnable."
        ),
        .jsonStructuredOutput: ScenarioRules(
            scenario: .jsonStructuredOutput,
            outputFormat: .strictJSON,
            verbosityTarget: .minimal,
            requiresCitations: false,
            strictJsonModePreferred: true,
            cliConstraintsEnabled: false,
            notes: "Schema-first contract with no trailing prose."
        ),
        .longformWriting: ScenarioRules(
            scenario: .longformWriting,
            outputFormat: .structuredMarkdown,
            verbosityTarget: .detailed,
            requiresCitations: false,
            strictJsonModePreferred: false,
            cliConstraintsEnabled: false,
            notes: "Enforce continuity and explicit uncertainty handling for factual statements."
        ),
        .researchSummarization: ScenarioRules(
            scenario: .researchSummarization,
            outputFormat: .citedSummary,
            verbosityTarget: .balanced,
            requiresCitations: true,
            strictJsonModePreferred: false,
            cliConstraintsEnabled: false,
            notes: "Citations and confidence labels should be explicit."
        ),
        .toolUsingAgent: ScenarioRules(
            scenario: .toolUsingAgent,
            outputFormat: .toolPlanOrManualPlan,
            verbosityTarget: .concise,
            requiresCitations: false,
            strictJsonModePreferred: false,
            cliConstraintsEnabled: false,
            notes: "Use tool loop instructions when model supports reliable tool usage; fallback otherwise."
        )
    ]
}
