import Foundation
import XCTest

final class PromptEngineViewModelIntentTests: XCTestCase {
    func testForgePromptStoryUsesCreativeContract() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Write me a story about a dog."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt
        XCTAssertTrue(output.localizedCaseInsensitiveContains("title, story"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("beginning, middle, and ending"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("execution-oriented"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("ordered implementation steps"))
    }

    func testForgePromptGameDesignUsesGameScaffold() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Design a tic-tac-toe game where the X's and the O's are made of cats and dogs."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt
        XCTAssertTrue(output.localizedCaseInsensitiveContains("concept, rules, visual theme"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("win/draw"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("cats and dogs"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("execution-oriented"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("ordered implementation steps"))
    }

    private func makeViewModel() -> (PromptEngineViewModel, () -> Void) {
        let folderName = "DexCraft-IntentTests-\(UUID().uuidString)"
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
