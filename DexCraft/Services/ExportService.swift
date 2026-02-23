import Foundation

final class ExportService {
    enum ExportError: Error {
        case promptNotFound
    }

    private let repository: PromptLibraryRepository
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let dateFormatter: ISO8601DateFormatter

    init(
        repository: PromptLibraryRepository = PromptLibraryRepository(),
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        self.dateFormatter = dateFormatter
    }

    func exportJSON(promptId: UUID, to url: URL) throws {
        let resolved = try resolvedPrompt(promptId: promptId)
        let payload = ExportPayload(
            prompt: resolved.prompt,
            versions: resolved.versions,
            categoryName: resolved.categoryName,
            tagNames: resolved.tagNames
        )
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    func exportMarkdown(promptId: UUID, to url: URL) throws {
        let resolved = try resolvedPrompt(promptId: promptId)
        let markdown = markdownContent(from: resolved)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportCSV(promptId: UUID, to url: URL) throws {
        let resolved = try resolvedPrompt(promptId: promptId)
        let header = "id,title,category,tags,createdAt,updatedAt,versionCount"
        let row = [
            resolved.prompt.id.uuidString,
            resolved.prompt.title,
            resolved.categoryName,
            resolved.tagNames.joined(separator: ";"),
            dateFormatter.string(from: resolved.prompt.createdAt),
            dateFormatter.string(from: resolved.prompt.updatedAt),
            String(resolved.versions.count)
        ].map(csvField).joined(separator: ",")

        let csv = "\(header)\n\(row)\n"
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportIDEBundle(promptId: UUID, to folderURL: URL) throws {
        let resolved = try resolvedPrompt(promptId: promptId)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let promptMarkdownURL = folderURL.appendingPathComponent("PROMPT.md", isDirectory: false)
        let metadataURL = folderURL.appendingPathComponent("METADATA.json", isDirectory: false)
        let versionsURL = folderURL.appendingPathComponent("VERSIONS.json", isDirectory: false)

        let markdown = markdownContent(from: resolved)
        try markdown.write(to: promptMarkdownURL, atomically: true, encoding: .utf8)

        let metadata = IDEBundleMetadata(
            id: resolved.prompt.id,
            title: resolved.prompt.title,
            category: resolved.categoryName,
            tags: resolved.tagNames,
            createdAt: resolved.prompt.createdAt,
            updatedAt: resolved.prompt.updatedAt,
            versionCount: resolved.versions.count
        )
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)

        let versionsData = try encoder.encode(resolved.versions)
        try versionsData.write(to: versionsURL, options: .atomic)
    }

    private func resolvedPrompt(promptId: UUID) throws -> ResolvedPrompt {
        guard let prompt = repository.prompts.first(where: { $0.id == promptId }) else {
            throw ExportError.promptNotFound
        }

        let categoryName = repository.categoryName(for: prompt.categoryId)
        let tagNames = repository.tagNames(for: prompt.tagIds).sorted {
            let lhs = $0.lowercased()
            let rhs = $1.lowercased()
            if lhs == rhs {
                return $0 < $1
            }
            return lhs < rhs
        }

        return ResolvedPrompt(
            prompt: prompt,
            versions: repository.versions(for: prompt.id),
            categoryName: categoryName,
            tagNames: tagNames
        )
    }

    private func markdownContent(from resolved: ResolvedPrompt) -> String {
        let tags = resolved.tagNames.map(yamlString).joined(separator: ", ")
        let title = yamlString(resolved.prompt.title)
        let category = yamlString(resolved.categoryName)

        return """
        ---
        title: \(title)
        category: \(category)
        tags: [\(tags)]
        ---

        \(resolved.prompt.body)
        """
    }

    private func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

private struct ResolvedPrompt {
    let prompt: PromptLibraryItem
    let versions: [PromptVersion]
    let categoryName: String
    let tagNames: [String]
}

private struct IDEBundleMetadata: Codable, Equatable {
    let id: UUID
    let title: String
    let category: String
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
    let versionCount: Int
}

private struct ExportPayload: Codable, Equatable {
    let prompt: PromptLibraryItem
    let versions: [PromptVersion]
    let categoryName: String
    let tagNames: [String]
}
