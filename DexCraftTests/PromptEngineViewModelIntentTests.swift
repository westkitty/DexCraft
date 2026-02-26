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

    func testEmbeddedRoutingRunsFallbackAcrossFiftyPrompts() throws {
        let sweepFlagPath = "/tmp/dexcraft-embedded-sweep.flag"
        guard FileManager.default.fileExists(atPath: sweepFlagPath) else {
            throw XCTSkip("Create \(sweepFlagPath) to run the 50-prompt embedded routing sweep.")
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimePath = repoRoot.appendingPathComponent("Tools/embedded-tiny-runtime/macos-arm64/llama-completion").path
        let modelPath = repoRoot.appendingPathComponent("Tools/embedded-tiny-runtime/macos-arm64/SmolLM2-135M-Instruct-Q3_K_M.gguf").path

        guard FileManager.default.isExecutableFile(atPath: runtimePath) else {
            throw XCTSkip("Embedded runtime executable missing at \(runtimePath)")
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("Embedded model missing at \(modelPath)")
        }

        setenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH", runtimePath, 1)
        defer { unsetenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH") }

        let invalidTinyModelPath = makeInvalidModelFile()
        defer { try? FileManager.default.removeItem(atPath: invalidTinyModelPath) }

        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        var settings = viewModel.connectedModelSettings
        settings.useEmbeddedTinyModel = true
        settings.useEmbeddedFallbackModel = true
        settings.embeddedTinyModelPath = invalidTinyModelPath
        settings.embeddedTinyModelIdentifier = "Invalid Tiny (Test)"
        settings.embeddedFallbackModelPath = modelPath
        settings.embeddedFallbackModelIdentifier = "Fallback Test Model"
        viewModel.updateConnectedModelSettings(settings)

        viewModel.autoOptimizePrompt = true
        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant

        let actions = [
            "Design a concise plan to",
            "Create a practical checklist to",
            "Write a concrete prompt to",
            "Draft testable requirements to",
            "Produce deterministic steps to"
        ]
        let topics = [
            "build a dog walking app",
            "organize a photo backup workflow",
            "create a local note-taking tool",
            "plan a weekly meal prep schedule",
            "improve a personal budget tracker",
            "set up a home lab backup policy",
            "prepare a small game prototype",
            "document an API migration path",
            "audit a local security checklist",
            "define acceptance criteria for a UI refresh"
        ]

        var prompts: [String] = []
        for action in actions {
            for topic in topics {
                prompts.append("\(action) \(topic).")
            }
        }
        XCTAssertEqual(prompts.count, 50)

        var fallbackStatusCount = 0
        for prompt in prompts {
            viewModel.roughInput = prompt
            viewModel.forgePrompt()

            let generated = viewModel.generatedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(generated.isEmpty, "Generated prompt should not be empty for input: \(prompt)")
            XCTAssertFalse(generated.lowercased().contains("here's a rewritten prompt"), "Wrapper text leaked for: \(prompt)")
            XCTAssertTrue(viewModel.tinyModelStatus.contains("Fallback model"), "Fallback tier did not run for: \(prompt)")
            fallbackStatusCount += 1
        }

        XCTAssertEqual(fallbackStatusCount, 50)
    }

    func testFallbackWithoutConfiguredPathDoesNotReportModelNotConfigured() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexcraft-mock-runtime-\(UUID().uuidString).sh")
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexcraft-mock-runtime-state-\(UUID().uuidString)")

        let script = """
        #!/bin/sh
        STATE_FILE="$1"
        shift
        if [ ! -f "$STATE_FILE" ]; then
          touch "$STATE_FILE"
          echo "forced primary failure" 1>&2
          exit 42
        fi
        echo "Design a website that clearly explains why this dog is cool, including personality, habits, and standout traits."
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: scriptURL.path)

        let wrapperURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexcraft-mock-runtime-wrapper-\(UUID().uuidString).sh")
        let wrapper = """
        #!/bin/sh
        "\(scriptURL.path)" "\(stateURL.path)" "$@"
        """
        try wrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: wrapperURL.path)

        defer {
            try? FileManager.default.removeItem(at: scriptURL)
            try? FileManager.default.removeItem(at: wrapperURL)
            try? FileManager.default.removeItem(at: stateURL)
        }

        setenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH", wrapperURL.path, 1)
        defer { unsetenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH") }

        let tinyModelPath = makeInvalidModelFile()
        defer { try? FileManager.default.removeItem(atPath: tinyModelPath) }

        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        var settings = viewModel.connectedModelSettings
        settings.useEmbeddedTinyModel = true
        settings.useEmbeddedFallbackModel = true
        settings.embeddedTinyModelPath = tinyModelPath
        settings.embeddedFallbackModelPath = nil
        viewModel.updateConnectedModelSettings(settings)

        viewModel.autoOptimizePrompt = true
        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.roughInput = "Design a website that explains how cool my dog is."
        viewModel.forgePrompt()

        XCTAssertTrue(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("fallback model"))
        XCTAssertFalse(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("not configured"))
        XCTAssertFalse(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("fallback model unavailable"))
    }

    func testTinyShortOutputCanStillApplyViaGoalRefinementFallback() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexcraft-short-output-runtime-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        echo "Remove all personal identifying information from the repository while preserving the username WestKitty."
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        setenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH", scriptURL.path, 1)
        defer { unsetenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH") }

        let tinyModelPath = makeInvalidModelFile()
        defer { try? FileManager.default.removeItem(atPath: tinyModelPath) }

        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        var settings = viewModel.connectedModelSettings
        settings.useEmbeddedTinyModel = true
        settings.useEmbeddedFallbackModel = false
        settings.embeddedTinyModelPath = tinyModelPath
        settings.embeddedFallbackModelPath = nil
        viewModel.updateConnectedModelSettings(settings)

        viewModel.autoOptimizePrompt = true
        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.roughInput = "Remove all personal identifying information from the repository. The only thing that you can keep is my username, WestKitty."
        viewModel.forgePrompt()

        XCTAssertTrue(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("tiny model pass applied"))
        XCTAssertFalse(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("failed validation"))
        XCTAssertTrue(viewModel.generatedPrompt.localizedCaseInsensitiveContains("westkitty"))
    }

    func testEmbeddedRuntimePIIPromptDoesNotEndInValidationFailure() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimePath = repoRoot.appendingPathComponent("Tools/embedded-tiny-runtime/macos-arm64/llama-completion").path
        let modelPath = repoRoot.appendingPathComponent("Tools/embedded-tiny-runtime/macos-arm64/SmolLM2-135M-Instruct-Q3_K_M.gguf").path

        guard FileManager.default.isExecutableFile(atPath: runtimePath) else {
            throw XCTSkip("Embedded runtime executable missing at \(runtimePath)")
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("Embedded model missing at \(modelPath)")
        }

        setenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH", runtimePath, 1)
        defer { unsetenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH") }

        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        var settings = viewModel.connectedModelSettings
        settings.useEmbeddedTinyModel = true
        settings.useEmbeddedFallbackModel = true
        settings.embeddedTinyModelPath = modelPath
        settings.embeddedFallbackModelPath = modelPath
        viewModel.updateConnectedModelSettings(settings)

        viewModel.autoOptimizePrompt = true
        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.roughInput = "Remove all personal identifying information from the repository. The only thing that you can keep is my username, WestKitty."
        viewModel.forgePrompt()

        XCTAssertFalse(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("failed validation"))
        XCTAssertTrue(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("pass applied"))
        XCTAssertTrue(viewModel.generatedPrompt.localizedCaseInsensitiveContains("westkitty"))
    }

    func testTinyLowOverlapTemplateOutputStillAppliesHintRefinementFallback() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexcraft-low-overlap-runtime-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        cat <<'OUT'
        ### Output Format
        Use sections in this order: Goal, Requirements, Constraints, Deliverables, Validation.
        Requirements must include concrete behavior and visual/interaction expectations.
        Validation must include deterministic checks tied to each requirement.
        ### Requirements
        - Translate the goal into concrete, testable functional requirements with explicit inputs/outputs.
        - Specify behavioral constraints and out-of-scope boundaries.
        OUT
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        setenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH", scriptURL.path, 1)
        defer { unsetenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH") }

        let tinyModelPath = makeInvalidModelFile()
        defer { try? FileManager.default.removeItem(atPath: tinyModelPath) }

        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        var settings = viewModel.connectedModelSettings
        settings.useEmbeddedTinyModel = true
        settings.useEmbeddedFallbackModel = false
        settings.embeddedTinyModelPath = tinyModelPath
        settings.embeddedFallbackModelPath = nil
        viewModel.updateConnectedModelSettings(settings)

        viewModel.autoOptimizePrompt = true
        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.roughInput = "Remove all personalized, identifying information from the GitHub repository. The only thing that you can keep is my username, WestKitty."
        viewModel.forgePrompt()

        XCTAssertTrue(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("tiny model pass applied"))
        XCTAssertFalse(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("failed validation"))
        XCTAssertTrue(viewModel.generatedPrompt.localizedCaseInsensitiveContains("westkitty"))
    }

    func testTinyOutputUnexpectedURLIsSanitizedWhenNotInInput() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexcraft-url-sanitize-runtime-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        cat <<'OUT'
        ### Goal
        [SimCity 3000](https://simcity.com/projects/3000/) Create a clone of SimCity 3000.
        ### Deliverables
        - Define requirements.
        OUT
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        setenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH", scriptURL.path, 1)
        defer { unsetenv("DEXCRAFT_EMBEDDED_RUNTIME_PATH") }

        let tinyModelPath = makeInvalidModelFile()
        defer { try? FileManager.default.removeItem(atPath: tinyModelPath) }

        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        var settings = viewModel.connectedModelSettings
        settings.useEmbeddedTinyModel = true
        settings.useEmbeddedFallbackModel = false
        settings.embeddedTinyModelPath = tinyModelPath
        settings.embeddedFallbackModelPath = nil
        viewModel.updateConnectedModelSettings(settings)

        viewModel.autoOptimizePrompt = true
        viewModel.selectedTarget = .claude
        viewModel.selectedScenarioProfile = .generalAssistant
        viewModel.roughInput = "Create a clone of SimCity 3000."
        viewModel.forgePrompt()

        XCTAssertFalse(viewModel.generatedPrompt.localizedCaseInsensitiveContains("https://"))
        XCTAssertFalse(viewModel.generatedPrompt.localizedCaseInsensitiveContains("simcity.com"))
        XCTAssertTrue(viewModel.tinyModelStatus.localizedCaseInsensitiveContains("pass applied"))
    }

    func testQualityGateGoalDefinedThresholdUsesTwelveCharacters() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.autoOptimizePrompt = false
        viewModel.roughInput = "abcdefghijk" // 11 chars
        viewModel.forgePrompt()

        guard let shortGoalCheck = viewModel.qualityChecks.first(where: { $0.title == "Goal Defined" }) else {
            return XCTFail("Missing Goal Defined check for short input.")
        }
        XCTAssertFalse(shortGoalCheck.passed)

        viewModel.roughInput = "abcdefghijkl" // 12 chars
        viewModel.forgePrompt()

        guard let longGoalCheck = viewModel.qualityChecks.first(where: { $0.title == "Goal Defined" }) else {
            return XCTFail("Missing Goal Defined check for 12-char input.")
        }
        XCTAssertTrue(longGoalCheck.passed)
    }

    func testQualityGateConstraintsActiveReflectsActiveConstraintCount() {
        let (viewModel, cleanup) = makeViewModel()
        defer { cleanup() }

        viewModel.autoOptimizePrompt = false
        viewModel.roughInput = "Create deterministic planner output."

        var options = EnhancementOptions()
        options.enforceMarkdown = false
        options.noConversationalFiller = false
        options.addFileTreeRequest = false
        options.includeVerificationChecklist = false
        options.includeRisksAndEdgeCases = false
        options.includeAlternatives = false
        options.includeValidationSteps = false
        options.includeRevertPlan = false
        options.preferSectionAwareParsing = false
        options.includeSearchVerificationRequirements = false
        options.strictCodeOnly = false
        viewModel.options = options
        viewModel.forgePrompt()

        guard let inactiveCheck = viewModel.qualityChecks.first(where: { $0.title == "Constraints Active" }) else {
            return XCTFail("Missing Constraints Active check when all options are disabled.")
        }
        XCTAssertFalse(inactiveCheck.passed)

        options.enforceMarkdown = true
        viewModel.options = options
        viewModel.forgePrompt()

        guard let activeCheck = viewModel.qualityChecks.first(where: { $0.title == "Constraints Active" }) else {
            return XCTFail("Missing Constraints Active check when one option is enabled.")
        }
        XCTAssertTrue(activeCheck.passed)
    }

    private func makeInvalidModelFile() -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexcraft-invalid-model-\(UUID().uuidString).gguf")
        let contents = Data("this-is-not-a-valid-gguf".utf8)
        try? contents.write(to: url, options: .atomic)
        return url.path
    }

    private func makeViewModel() -> (PromptEngineViewModel, () -> Void) {
        let folderName = "DexCraft-IntentTests-\(UUID().uuidString)"
        let storageManager = StorageManager(appFolderName: folderName)
        let repository = PromptLibraryRepository(storageBackend: InMemoryStorageBackend(), filename: "prompt-library-tests.json")
        let viewModel = PromptEngineViewModel(
            storageManager: storageManager,
            promptLibraryRepository: repository
        )
        var settings = viewModel.connectedModelSettings
        settings.useEmbeddedTinyModel = false
        settings.useEmbeddedFallbackModel = false
        viewModel.updateConnectedModelSettings(settings)

        let cleanup = {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            let folderURL = baseURL.appendingPathComponent(folderName, isDirectory: true)
            try? FileManager.default.removeItem(at: folderURL)
        }

        return (viewModel, cleanup)
    }
}
