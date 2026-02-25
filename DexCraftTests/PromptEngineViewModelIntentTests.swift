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
        XCTAssertTrue(output.localizedCaseInsensitiveContains("complete short story"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("beginning, middle, and ending"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("narrative voice"))
        XCTAssertFalse(output.contains("### Output Contract"))
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
        XCTAssertTrue(output.localizedCaseInsensitiveContains("objective, setup, turn order"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("deterministic win/draw"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("cats and dogs"))
        XCTAssertFalse(output.contains("### Output Format"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("execution-oriented"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("ordered implementation steps"))
    }

    func testForgePromptSoftwareBuildUsesRequirementDrivenContract() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Create a 2D Super Nintendo style platformer, starring a dog."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt
        XCTAssertTrue(output.localizedCaseInsensitiveContains("movement, physics"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("deterministic test scenarios"))
        XCTAssertFalse(output.contains("### Output Format"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("execution-oriented"))
    }

    func testForgePromptIDEAvoidsGenericContractAndDuplicateDeliverableSets() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .ideCodingAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Add a bunch of new flashy animations to this website so that it feels more lively."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt
        XCTAssertTrue(output.localizedCaseInsensitiveContains("goal, plan, deliverables, validation"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("execution-oriented"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("plan with deterministic ordered steps"))
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
