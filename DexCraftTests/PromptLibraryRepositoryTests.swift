import XCTest

final class PromptLibraryRepositoryTests: XCTestCase {
    private var storageBackend: InMemoryStorageBackend!
    private let filename = "prompt-library-tests.json"

    override func setUp() {
        super.setUp()
        storageBackend = InMemoryStorageBackend()
    }

    func testRoundTripSaveLoadAndSorting() {
        let repository = makeRepository()
        seedLibrary(in: repository, includeLCSBody: false)

        repository.persist()
        let reloaded = makeRepository()

        XCTAssertEqual(reloaded.categories.count, 2)
        XCTAssertEqual(reloaded.tags.count, 3)
        XCTAssertEqual(reloaded.prompts.count, 3)
        XCTAssertEqual(reloaded.categories.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(reloaded.prompts.map(\.title), ["Builder Refactor", "Export Formats", "UI polish"])
    }

    func testSearchByTitle() {
        let repository = makeRepository()
        seedLibrary(in: repository, includeLCSBody: false)

        let results = repository.searchPrompts(query: "export")
        XCTAssertEqual(results.map(\.title), ["Export Formats"])
    }

    func testSearchByBody() {
        let repository = makeRepository()
        seedLibrary(in: repository, includeLCSBody: true)

        let results = repository.searchPrompts(query: "lcs")
        XCTAssertEqual(results.map(\.title), ["Builder Refactor"])
    }

    func testSearchByTag() {
        let repository = makeRepository()
        seedLibrary(in: repository, includeLCSBody: false)

        let results = repository.searchPrompts(query: "ui")
        XCTAssertEqual(results.map(\.title), ["UI polish"])
    }

    func testDeleteCategoryMakesPromptsUncategorized() {
        let repository = makeRepository()
        seedLibrary(in: repository, includeLCSBody: false)

        guard let personalCategory = repository.categories.first(where: { $0.name == "Personal" }) else {
            return XCTFail("Missing Personal category")
        }

        repository.deleteCategory(id: personalCategory.id)
        let reloaded = makeRepository()

        XCTAssertFalse(reloaded.categories.contains(where: { $0.name == "Personal" }))

        guard let exportPrompt = reloaded.prompts.first(where: { $0.title == "Export Formats" }) else {
            return XCTFail("Missing Export Formats prompt")
        }

        XCTAssertNil(exportPrompt.categoryId)
    }

    private func makeRepository() -> PromptLibraryRepository {
        PromptLibraryRepository(storageBackend: storageBackend, filename: filename)
    }

    private func seedLibrary(in repository: PromptLibraryRepository, includeLCSBody: Bool) {
        guard
            let workCategory = repository.createCategory(name: "Work"),
            let personalCategory = repository.createCategory(name: "Personal"),
            let swiftTag = repository.createTag(name: "swift"),
            let uiTag = repository.createTag(name: "ui"),
            let exportTag = repository.createTag(name: "export")
        else {
            XCTFail("Failed to create categories/tags")
            return
        }

        let builderBody = includeLCSBody ? "Use LCS diff engine and preserve command determinism." : "Refactor the builder flow."

        XCTAssertNotNil(
            repository.createPrompt(
                title: "Builder Refactor",
                body: builderBody,
                categoryId: workCategory.id,
                tagIds: [swiftTag.id]
            )
        )

        XCTAssertNotNil(
            repository.createPrompt(
                title: "UI polish",
                body: "Polish component spacing and typography consistency.",
                categoryId: workCategory.id,
                tagIds: [uiTag.id, swiftTag.id]
            )
        )

        XCTAssertNotNil(
            repository.createPrompt(
                title: "Export Formats",
                body: "Enumerate export formats and metadata fields.",
                categoryId: personalCategory.id,
                tagIds: [exportTag.id]
            )
        )
    }
}
