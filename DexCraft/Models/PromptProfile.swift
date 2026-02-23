import Foundation

enum PromptFormatStyle: String, Codable {
    case claudeXML
    case markdownHeadings
    case agenticIDE
    case perplexitySearch
}

struct ConnectedModelSettings: Codable, Equatable {
    static let unknownUnsetLabel = "unknown/unset"

    // TODO: Replace defaults with exact connected model versions from Settings once known.
    var claudeModelVersion: String = ConnectedModelSettings.unknownUnsetLabel
    var geminiChatGPTModelVersion: String = ConnectedModelSettings.unknownUnsetLabel
    var perplexityModelVersion: String = ConnectedModelSettings.unknownUnsetLabel
    var agenticIDEModelVersion: String = ConnectedModelSettings.unknownUnsetLabel

    func modelNames(for target: PromptTarget) -> [String] {
        let raw: String

        switch target {
        case .claude:
            raw = claudeModelVersion
        case .geminiChatGPT:
            raw = geminiChatGPTModelVersion
        case .perplexity:
            raw = perplexityModelVersion
        case .agenticIDE:
            raw = agenticIDEModelVersion
        }

        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.lowercased() == ConnectedModelSettings.unknownUnsetLabel {
            return []
        }

        return [cleaned]
    }
}

struct PromptProfile {
    let target: PromptTarget
    let provider: String
    let modelNames: [String]
    let formatStyle: PromptFormatStyle
    let defaultSystemPreambleLines: [String]
    let outputContractLines: [String]
    let pitfallsAvoidLines: [String]
    let tacticsLines: [String]

    static func profile(for target: PromptTarget, settings: ConnectedModelSettings) -> PromptProfile {
        switch target {
        case .claude:
            return PromptProfile(
                target: target,
                provider: "Anthropic",
                modelNames: settings.modelNames(for: target),
                formatStyle: .claudeXML,
                defaultSystemPreambleLines: [
                    "Use XML tags to separate objective, context, requirements, constraints, and deliverables.",
                    "Keep sections explicit and deterministic."
                ],
                outputContractLines: [
                    "Return only the requested sections.",
                    "Preserve every hard constraint and explicit deliverable."
                ],
                pitfallsAvoidLines: [
                    "Do not blend goal and context into the same block.",
                    "Do not omit required sections when input is run-on."
                ],
                tacticsLines: [
                    "Use concise bullets inside XML tags for list sections.",
                    "Prefer explicit, implementation-ready language."
                ]
            )
        case .geminiChatGPT:
            return PromptProfile(
                target: target,
                provider: "OpenAI/Google",
                modelNames: settings.modelNames(for: target),
                formatStyle: .markdownHeadings,
                defaultSystemPreambleLines: [
                    "Use strict markdown headings for each section.",
                    "Keep section boundaries explicit."
                ],
                outputContractLines: [
                    "Respond with structured markdown sections only.",
                    "Prioritize concise, actionable phrasing."
                ],
                pitfallsAvoidLines: [
                    "Avoid narrative filler between sections.",
                    "Avoid collapsing requirements into context."
                ],
                tacticsLines: [
                    "Use bullet lists for requirements, constraints, and deliverables.",
                    "Keep ordering stable across runs."
                ]
            )
        case .perplexity:
            return PromptProfile(
                target: target,
                provider: "Perplexity",
                modelNames: settings.modelNames(for: target),
                formatStyle: .perplexitySearch,
                defaultSystemPreambleLines: [
                    "Use structured markdown with explicit research constraints.",
                    "Separate objective, requirements, and verification expectations."
                ],
                outputContractLines: [
                    "Cite sources for factual claims using markdown links.",
                    "Flag uncertainty when evidence is incomplete or conflicting."
                ],
                pitfallsAvoidLines: [
                    "Do not provide uncited factual claims.",
                    "Do not skip verification requirements."
                ],
                tacticsLines: [
                    "State search and verification requirements before synthesis.",
                    "Keep citations attached to the corresponding claims."
                ]
            )
        case .agenticIDE:
            return PromptProfile(
                target: target,
                provider: "IDE Agents (Cursor/Windsurf/Copilot)",
                modelNames: settings.modelNames(for: target),
                formatStyle: .agenticIDE,
                defaultSystemPreambleLines: [
                    "Use implementation-first sections with deterministic ordering.",
                    "Keep instructions aligned to patch + test workflows."
                ],
                outputContractLines: [
                    "Produce plan, diff summary, tests, and validation commands.",
                    "Keep output directly usable in coding workflows."
                ],
                pitfallsAvoidLines: [
                    "Do not skip test or validation sections.",
                    "Do not hide assumptions in prose."
                ],
                tacticsLines: [
                    "Tie requirements to concrete file or command actions.",
                    "Keep patch and validation steps auditable."
                ]
            )
        }
    }
}
