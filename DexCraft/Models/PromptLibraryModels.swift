import Foundation

struct PromptVersion: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let note: String?
    let content: String

    init(id: UUID = UUID(), createdAt: Date = Date(), note: String? = nil, content: String) {
        self.id = id
        self.createdAt = createdAt
        self.note = note
        self.content = content
    }
}

struct PromptLibraryItem: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var body: String
    var categoryId: UUID?
    var tagIds: [UUID]
    var versions: [PromptVersion]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        categoryId: UUID? = nil,
        tagIds: [UUID] = [],
        versions: [PromptVersion] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.categoryId = categoryId
        self.tagIds = tagIds
        self.versions = versions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case categoryId
        case tagIds
        case versions
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        tagIds = try container.decodeIfPresent([UUID].self, forKey: .tagIds) ?? []
        versions = try container.decodeIfPresent([PromptVersion].self, forKey: .versions) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct PromptCategory: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct PromptTag: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct PromptLibraryBundle: Codable, Equatable {
    var categories: [PromptCategory]
    var tags: [PromptTag]
    var prompts: [PromptLibraryItem]

    static let empty = PromptLibraryBundle(categories: [], tags: [], prompts: [])
}

struct PromptRunRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let promptId: UUID
    let timestamp: Date
    let inputLengthChars: Int
    let outputLengthChars: Int
    let estimatedTokensInput: Int
    let estimatedTokensOutput: Int
    let adapterId: String
    let durationMs: Int

    init(
        id: UUID = UUID(),
        promptId: UUID,
        timestamp: Date = Date(),
        inputLengthChars: Int,
        outputLengthChars: Int,
        estimatedTokensInput: Int,
        estimatedTokensOutput: Int,
        adapterId: String,
        durationMs: Int
    ) {
        self.id = id
        self.promptId = promptId
        self.timestamp = timestamp
        self.inputLengthChars = inputLengthChars
        self.outputLengthChars = outputLengthChars
        self.estimatedTokensInput = estimatedTokensInput
        self.estimatedTokensOutput = estimatedTokensOutput
        self.adapterId = adapterId
        self.durationMs = durationMs
    }
}

enum TokenEstimator {
    static func estimate(for text: String) -> Int {
        let charCount = text.count
        return max(1, Int(ceil(Double(charCount) / 4.0)))
    }
}
