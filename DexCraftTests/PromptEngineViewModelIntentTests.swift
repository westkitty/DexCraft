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

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("platformer"))
        XCTAssertTrue(output.contains("movement") || output.contains("physics"))
        XCTAssertTrue(output.contains("deterministic"))
        XCTAssertFalse(output.contains("translate the request into concrete functional requirements"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("execution-oriented"))
    }

    func testForgePromptSoftwareBuildRetainsConcreteTaskAnchors() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Make me a snake game, set in the 1700s."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("snake"))
        XCTAssertTrue(output.contains("1700"))
        XCTAssertFalse(output.contains("translate the request into concrete functional requirements"))
    }

    func testForgePromptMinecraftCloneGetsDomainSpecificRequirements() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Build me a Minecraft Clone."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("minecraft"))
        XCTAssertTrue(output.contains("crafting"))
        XCTAssertTrue(output.contains("inventory"))
        XCTAssertTrue(output.contains("block"))
    }

    func testForgePromptGeneralListUsesSemanticRewriteInsteadOfGenericContract() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Create a list of 10 different ways to tell somebody they smile like a dog."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt
        XCTAssertFalse(output.contains("### Output Contract"))
        XCTAssertFalse(output.contains("### Deliverables"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("execution-oriented"))
    }

    func testForgePromptGeneralListStaysSemanticWhenTargetStateIsAgenticIDE() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .agenticIDE
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Create a list of 10 different ways to tell somebody they smile like a dog."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt
        XCTAssertFalse(output.contains("### Output Contract"))
        XCTAssertFalse(output.contains("### Deliverables"))
        XCTAssertFalse(output.contains("### Goal"))
    }

    func testForgePromptZipFileListRequestStaysGroundedToZipContext() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "In the code box, give me a list of all the file names inside this zip file."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("zip"))
        XCTAssertTrue(output.contains("file"))
        XCTAssertTrue(output.contains("name"))
        XCTAssertFalse(output.contains("translate the request into concrete functional requirements"))
        XCTAssertFalse(output.contains("### output contract"))
    }

    func testForgePromptHoroscopeRequestAvoidsGenericRequirementContractLanguage() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .geminiChatGPT
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Tell me my horoscope and the horoscope of my dog."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("horoscope"))
        XCTAssertFalse(output.contains("make requirements explicit"))
        XCTAssertFalse(output.contains("completion checks tied to the requested artifact"))
    }

    func testForgePromptWebsiteRequestAvoidsTinyMetaWrapperLanguage() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .ideCodingAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Design a website that will explain how cool my dog is."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("website"))
        XCTAssertTrue(output.contains("dog"))
        XCTAssertFalse(output.contains("rewritten prompt"))
        XCTAssertFalse(output.contains("i made several changes"))
    }

    func testForgePromptMarioGameRequestDoesNotInjectAnimationTemplate() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .ideCodingAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Make a Mario style game about cats."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("mario") || output.contains("cats"))
        XCTAssertFalse(output.contains("animation constraints"))
        XCTAssertFalse(output.contains("surfaces/components"))
    }

    func testForgePromptPoemUsesPoemLanguageNotStoryScaffold() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .longformWriting
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Write me a poem about my dog and his wonderful way of being."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("poem"))
        XCTAssertFalse(output.contains("short story"))
        XCTAssertFalse(output.contains("### output contract"))
    }

    func testForgePromptIDEAvoidsGenericContractAndDuplicateDeliverableSets() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .ideCodingAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Add a bunch of new flashy animations to this website so that it feels more lively."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertTrue(output.contains("animation"))
        XCTAssertTrue(output.contains("validation"))
        XCTAssertFalse(output.contains("execution-oriented"))
        XCTAssertFalse(output.contains("plan with deterministic ordered steps"))
    }

    func testForgePromptIDENonCodingPromptAvoidsAnimationTemplate() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.selectedTarget = .geminiChatGPT
        viewModel.selectedScenarioProfile = .ideCodingAssistant
        viewModel.autoOptimizePrompt = true
        viewModel.roughInput = "Find the most useful file I've got about monkeys."
        viewModel.forgePrompt()

        let output = viewModel.generatedPrompt.lowercased()
        XCTAssertFalse(output.contains("animation goals"))
        XCTAssertFalse(output.contains("new animations"))
        XCTAssertFalse(output.contains("### output contract"))
        XCTAssertTrue(output.contains("monkeys"))
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
