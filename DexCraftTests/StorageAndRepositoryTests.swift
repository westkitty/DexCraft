import XCTest

final class StorageAndRepositoryTests: XCTestCase {
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
}
