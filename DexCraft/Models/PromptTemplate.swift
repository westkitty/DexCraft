import Foundation

struct PromptTemplate: Codable, Identifiable {
    let id: UUID
    var name: String
    var content: String
    var target: PromptTarget
    var createdAt: Date

    init(id: UUID = UUID(), name: String, content: String, target: PromptTarget, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.target = target
        self.createdAt = createdAt
    }
}
