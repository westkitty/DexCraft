import XCTest

final class StorageAndRepositoryTests: XCTestCase {
    private final class ThrowingLoadBackend: StorageBackend {
        struct DecodeFailure: Error {}
        var saveCount = 0

        func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
            throw DecodeFailure()
        }

        func save<T: Encodable>(_ value: T, to filename: String) throws {
            saveCount += 1
        }

        func delete(_ filename: String) throws {}
    }

    private let filename = "storage-and-repository-tests.json"

    func testInMemoryRoundTrip() throws {
        struct SamplePayload: Codable, Equatable {
            let id: UUID
            let name: String
            let values: [String]
        }

        let backend = InMemoryStorageBackend()
        let payload = SamplePayload(id: UUID(), name: "DexCraft", values: ["a", "b", "c"])

        try backend.save(payload, to: filename)
        let loaded = try backend.load(SamplePayload.self, from: filename)

        XCTAssertEqual(loaded, payload)
    }

    func testHistoryCapEnforcement() {
        let backend = InMemoryStorageBackend()
        let repository = PromptLibraryRepository(storageBackend: backend, filename: filename)

        guard let prompt = repository.createPrompt(title: "Version Cap Prompt", body: "v0") else {
            return XCTFail("Failed to create prompt")
        }

        for index in 1...60 {
            repository.updatePromptBody(promptId: prompt.id, body: "v\(index)")
        }

        repository.persist()
        let reloaded = PromptLibraryRepository(storageBackend: backend, filename: filename)
        let versions = reloaded.versions(for: prompt.id)

        XCTAssertEqual(versions.count, 50)
        XCTAssertEqual(versions.first?.content, "v60")
    }

    func testStableSortingBeforeSave() {
        let backend = InMemoryStorageBackend()
        let repository = PromptLibraryRepository(storageBackend: backend, filename: filename)

        guard
            let categoryWork = repository.createCategory(name: "Work"),
            let categoryPersonal = repository.createCategory(name: "personal"),
            let categoryAlpha = repository.createCategory(name: "Alpha"),
            let tagZeta = repository.createTag(name: "zeta"),
            let tagBeta = repository.createTag(name: "Beta"),
            let tagAlpha = repository.createTag(name: "alpha")
        else {
            return XCTFail("Failed to seed categories/tags")
        }

        XCTAssertNotNil(
            repository.createPrompt(
                title: "z task",
                body: "Prompt Z",
                categoryId: categoryWork.id,
                tagIds: [tagZeta.id]
            )
        )
        XCTAssertNotNil(
            repository.createPrompt(
                title: "A task",
                body: "Prompt A",
                categoryId: categoryPersonal.id,
                tagIds: [tagBeta.id]
            )
        )
        XCTAssertNotNil(
            repository.createPrompt(
                title: "m task",
                body: "Prompt M",
                categoryId: categoryAlpha.id,
                tagIds: [tagAlpha.id]
            )
        )

        repository.persist()
        let reloaded = PromptLibraryRepository(storageBackend: backend, filename: filename)

        XCTAssertEqual(reloaded.categories.map(\.name), ["Alpha", "personal", "Work"])
        XCTAssertEqual(reloaded.tags.map(\.name), ["alpha", "Beta", "zeta"])
        XCTAssertEqual(reloaded.prompts.map(\.title), ["A task", "m task", "z task"])
    }

    func testReloadDecodeFailureDoesNotPersistEmptyBundle() {
        let backend = ThrowingLoadBackend()
        _ = PromptLibraryRepository(storageBackend: backend, filename: filename)
        XCTAssertEqual(backend.saveCount, 0)
    }

    func testTemplateMigrationDefaultsFromOldJSONFixture() throws {
        let migrationFallback = ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!
        let previousMigrationClock = PromptTemplate.migrationNow
        PromptTemplate.migrationNow = { migrationFallback }
        defer { PromptTemplate.migrationNow = previousMigrationClock }

        let oldJSON = """
        [
          {
            "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            "name": "Legacy One",
            "content": "content",
            "target": "Claude",
            "createdAt": "2024-07-01T12:00:00Z"
          },
          {
            "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            "name": "Legacy Two",
            "content": "content",
            "target": "Perplexity",
            "createdAt": "not-a-date"
          }
        ]
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([PromptTemplate].self, from: Data(oldJSON.utf8))

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].category, PromptTemplate.uncategorizedCategory)
        XCTAssertEqual(decoded[0].tags, [])
        XCTAssertEqual(decoded[0].updatedAt, decoded[0].createdAt)
        XCTAssertEqual(decoded[1].createdAt, migrationFallback)
        XCTAssertEqual(decoded[1].updatedAt, migrationFallback)
    }

    func testDeterministicFilteringComposesCategoryTargetAndSearch() {
        let templates = [
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Alpha Plan",
                category: "Planning",
                tags: ["security", "offline"],
                target: .claude,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-02-01T00:00:00Z"
            ),
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Beta Checklist",
                category: "Planning",
                tags: ["network"],
                target: .geminiChatGPT,
                createdAt: "2024-01-02T00:00:00Z",
                updatedAt: "2024-02-02T00:00:00Z"
            ),
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Security Audit",
                category: "Security",
                tags: ["planning"],
                target: .claude,
                createdAt: "2024-01-03T00:00:00Z",
                updatedAt: "2024-02-03T00:00:00Z"
            )
        ]

        let visible = computeVisibleTemplates(
            templates: templates,
            query: "security",
            categoryFilter: "Planning",
            targetFilter: .claude,
            sort: .recentlyUpdated,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(visible.map(\.id.uuidString), ["00000000-0000-0000-0000-000000000001"])
    }

    func testDeterministicSortingUsesExpectedTieBreakers() {
        let templates = [
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Alpha",
                category: "General",
                tags: [],
                target: .claude,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-03-01T00:00:00Z"
            ),
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Alpha",
                category: "General",
                tags: [],
                target: .claude,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-03-01T00:00:00Z"
            ),
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Beta",
                category: "General",
                tags: [],
                target: .claude,
                createdAt: "2024-01-02T00:00:00Z",
                updatedAt: "2024-02-28T00:00:00Z"
            )
        ]

        let updatedOrder = computeVisibleTemplates(
            templates: templates,
            query: "",
            categoryFilter: nil,
            targetFilter: nil,
            sort: .recentlyUpdated,
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(
            updatedOrder.map(\.id.uuidString),
            [
                "00000000-0000-0000-0000-000000000002",
                "00000000-0000-0000-0000-000000000003",
                "00000000-0000-0000-0000-000000000001"
            ]
        )

        let nameOrder = computeVisibleTemplates(
            templates: templates,
            query: "",
            categoryFilter: nil,
            targetFilter: nil,
            sort: .nameAscending,
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertEqual(
            nameOrder.map(\.id.uuidString),
            [
                "00000000-0000-0000-0000-000000000002",
                "00000000-0000-0000-0000-000000000003",
                "00000000-0000-0000-0000-000000000001"
            ]
        )
    }

    func testCategoryRenameMergeDeletePropagation() {
        let seed = [
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                name: "One",
                category: "Alpha",
                tags: [],
                target: .claude,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-01-01T00:00:00Z"
            ),
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                name: "Two",
                category: "Beta",
                tags: [],
                target: .claude,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-01-01T00:00:00Z"
            )
        ]

        let renamed = TemplateCategoryOperations.renameCategory(templates: seed, from: "Alpha", to: "Gamma")
        XCTAssertEqual(renamed.first?.category, "Gamma")

        let merged = TemplateCategoryOperations.mergeCategory(templates: renamed, source: "Beta", destination: "Gamma")
        XCTAssertTrue(merged.allSatisfy { $0.category == "Gamma" })

        let deleted = TemplateCategoryOperations.deleteCategory(templates: merged, category: "Gamma")
        XCTAssertTrue(deleted.allSatisfy { $0.category == PromptTemplate.uncategorizedCategory })
    }

    func testImportDefaultsIsIdempotent() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        for template in viewModel.templates {
            viewModel.deleteTemplate(template)
        }

        let defaults = [
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                name: "Default A",
                category: "Planning",
                tags: ["one"],
                target: .claude,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-01-02T00:00:00Z"
            ),
            makeTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                name: "Default B",
                category: "Testing",
                tags: ["two"],
                target: .geminiChatGPT,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-01-02T00:00:00Z"
            )
        ]

        let firstImport = viewModel.importDefaultTemplates(defaults)
        let secondImport = viewModel.importDefaultTemplates(defaults)

        XCTAssertEqual(firstImport, 2)
        XCTAssertEqual(secondImport, 0)
    }

    private func makeTemplate(
        id: UUID,
        name: String,
        category: String,
        tags: [String],
        target: PromptTarget,
        createdAt: String,
        updatedAt: String
    ) -> PromptTemplate {
        let formatter = ISO8601DateFormatter()
        let created = formatter.date(from: createdAt) ?? Date(timeIntervalSince1970: 0)
        let updated = formatter.date(from: updatedAt) ?? created
        return PromptTemplate(
            id: id,
            name: name,
            content: "body",
            target: target,
            createdAt: created,
            category: category,
            tags: tags,
            updatedAt: updated
        )
    }

    private func makeViewModel() -> (PromptEngineViewModel, () -> Void) {
        let folderName = "DexCraft-StorageTests-\(UUID().uuidString)"
        let storageManager = StorageManager(appFolderName: folderName)
        let repository = PromptLibraryRepository(storageBackend: InMemoryStorageBackend(), filename: "prompt-library-tests.json")
        let viewModel = PromptEngineViewModel(
            storageManager: storageManager,
            promptLibraryRepository: repository
        )

        let cleanup = {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            let folderURL = baseURL.appendingPathComponent(folderName, isDirectory: true)
            try? FileManager.default.removeItem(at: folderURL)
        }

        return (viewModel, cleanup)
    }
}
