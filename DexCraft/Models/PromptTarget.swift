import Foundation

enum PromptTarget: String, CaseIterable, Codable, Identifiable {
    case claude = "Claude"
    case geminiChatGPT = "Gemini/ChatGPT"
    case perplexity = "Perplexity"
    case agenticIDE = "Agentic IDE (Cursor/Windsurf/Copilot)"

    var id: String { rawValue }

    var segmentTitle: String {
        switch self {
        case .claude:
            return "Claude"
        case .geminiChatGPT:
            return "Gemini/ChatGPT"
        case .perplexity:
            return "Perplexity"
        case .agenticIDE:
            return "Agentic IDE"
        }
    }
}
