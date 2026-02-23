import XCTest

final class ExportServiceTests: XCTestCase {
    private var storageBackend: InMemoryStorageBackend!
    private var repository: PromptLibraryRepository!
    private var exportService: ExportService!
    private var tempDirectory: URL!
    private var promptId: UUID!

    override func setUp() {
        super.setUp()

        storageBackend = InMemoryStorageBackend()
        repository = PromptLibraryRepository(storageBackend: storageBackend, filename: "export-service-tests.json")
        exportService = ExportService(repository: repository)

        let base = FileManager.default.temporaryDirectory
        tempDirectory = base.appendingPathComponent("dexcraft-export-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        seedLibrary()
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        exportService = nil
        repository = nil
        storageBackend = nil
        promptId = nil
        tempDirectory = nil

        super.tearDown()
    }

    func testJSONExportValid() throws {
        let fileURL = tempDirectory.appendingPathComponent("prompt.json", isDirectory: false)
        try exportService.exportJSON(promptId: promptId, to: fileURL)

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(TestExportPayload.self, from: data)

        XCTAssertEqual(payload.prompt.id, promptId)
        XCTAssertEqual(payload.versions.count, repository.versions(for: promptId).count)
    }

    func testMarkdownContainsFrontMatterAndContent() throws {
        let fileURL = tempDirectory.appendingPathComponent("prompt.md", isDirectory: false)
        try exportService.exportMarkdown(promptId: promptId, to: fileURL)

        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        let promptBody = try XCTUnwrap(repository.prompts.first(where: { $0.id == promptId })?.body)

        XCTAssertTrue(markdown.hasPrefix("---"))
        XCTAssertTrue(markdown.contains("title:"))
        XCTAssertTrue(markdown.contains(promptBody))
    }

    func testCSVHeaderExact() throws {
        let fileURL = tempDirectory.appendingPathComponent("prompt.csv", isDirectory: false)
        try exportService.exportCSV(promptId: promptId, to: fileURL)

        let csv = try String(contentsOf: fileURL, encoding: .utf8)
        let firstLine = csv.components(separatedBy: .newlines).first ?? ""
        XCTAssertEqual(firstLine, "id,title,category,tags,createdAt,updatedAt,versionCount")
    }

    func testIDEBundleCreatesFiles() throws {
        let bundleURL = tempDirectory.appendingPathComponent("bundle", isDirectory: true)
        try exportService.exportIDEBundle(promptId: promptId, to: bundleURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("PROMPT.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("METADATA.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("VERSIONS.json").path))
    }

    private func seedLibrary() {
        guard
            let category = repository.createCategory(name: "Work"),
            let swiftTag = repository.createTag(name: "swift"),
            let uiTag = repository.createTag(name: "ui"),
            let prompt = repository.createPrompt(
                title: "Export Prompt",
                body: "Initial export content",
                categoryId: category.id,
                tagIds: [uiTag.id, swiftTag.id]
            )
        else {
            XCTFail("Failed to seed repository for export tests.")
            return
        }

        repository.updatePromptBody(promptId: prompt.id, body: "Latest export content")
        promptId = prompt.id
    }
}

private struct TestExportPayload: Codable, Equatable {
    let prompt: PromptLibraryItem
    let versions: [PromptVersion]
    let categoryName: String
    let tagNames: [String]
}
