import XCTest

final class PromptVersioningTests: XCTestCase {
    private var storageBackend: InMemoryStorageBackend!
    private let filename = "prompt-versioning-tests.json"

    override func setUp() {
        super.setUp()
        storageBackend = InMemoryStorageBackend()
    }

    func testInitialSaveCreatesBaselineVersion() {
        let repository = makeRepository()
        let prompt = makePrompt(in: repository)

        let versions = repository.versions(for: prompt.id)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions[0].content, "v1")
    }

    func testSaveChangeCreatesNewVersion() {
        let repository = makeRepository()
        let prompt = makePrompt(in: repository)

        repository.updatePromptBody(promptId: prompt.id, body: "v2")
        repository.updatePromptBody(promptId: prompt.id, body: "v3")

        let versions = repository.versions(for: prompt.id)
        XCTAssertEqual(versions.count, 3)
        XCTAssertEqual(versions[0].content, "v3")
    }

    func testSaveIdenticalDoesNotCreateVersion() {
        let repository = makeRepository()
        let prompt = makePrompt(in: repository)

        repository.updatePromptBody(promptId: prompt.id, body: "v2")
        repository.updatePromptBody(promptId: prompt.id, body: "v3")
        repository.updatePromptBody(promptId: prompt.id, body: "v3")

        let versions = repository.versions(for: prompt.id)
        XCTAssertEqual(versions.count, 3)
    }

    func testRollbackCreatesNewVersionAndSetsBody() throws {
        let repository = makeRepository()
        let prompt = makePrompt(in: repository)

        repository.updatePromptBody(promptId: prompt.id, body: "v2")
        repository.updatePromptBody(promptId: prompt.id, body: "v3")

        guard let v1Version = repository.versions(for: prompt.id).first(where: { $0.content == "v1" }) else {
            return XCTFail("Missing v1 version")
        }

        try repository.rollback(promptId: prompt.id, to: v1Version.id)

        guard let rolledPrompt = repository.prompts.first(where: { $0.id == prompt.id }) else {
            return XCTFail("Missing prompt after rollback")
        }

        let versions = repository.versions(for: prompt.id)
        XCTAssertEqual(rolledPrompt.body, "v1")
        XCTAssertEqual(versions.count, 4)
        XCTAssertEqual(versions[0].content, "v1")
        XCTAssertTrue(versions[0].note?.lowercased().contains("rollback") == true)
    }

    private func makeRepository() -> PromptLibraryRepository {
        PromptLibraryRepository(storageBackend: storageBackend, filename: filename)
    }

    private func makePrompt(in repository: PromptLibraryRepository) -> PromptLibraryItem {
        guard let prompt = repository.createPrompt(title: "Versioned Prompt", body: "v1") else {
            XCTFail("Failed to create prompt")
            fatalError("Prompt creation failed")
        }

        return prompt
    }
}
