import Foundation

struct PromptHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let target: PromptTarget
    let originalInput: String
    let generatedPrompt: String
    let options: EnhancementOptions
    let variables: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        target: PromptTarget,
        originalInput: String,
        generatedPrompt: String,
        options: EnhancementOptions,
        variables: [String: String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.target = target
        self.originalInput = originalInput
        self.generatedPrompt = generatedPrompt
        self.options = options
        self.variables = variables
    }
}
