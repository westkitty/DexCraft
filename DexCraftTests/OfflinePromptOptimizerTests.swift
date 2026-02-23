import XCTest

final class OfflinePromptOptimizerTests: XCTestCase {
    private let optimizer = OfflinePromptOptimizer()

    func testLocalCLICLIAssistantProducesCommandForwardPrompt() {
        let output = optimizer.optimize(
            OptimizationInput(
                rawUserPrompt: "List tracked git files and run the test suite.",
                modelFamily: .localCLIRuntimes,
                scenario: .cliAssistant,
                userOverrides: nil
            )
        )

        XCTAssertTrue(output.optimizedPrompt.localizedCaseInsensitiveContains("shell commands only"))
        XCTAssertTrue(output.optimizedPrompt.localizedCaseInsensitiveContains("copy/paste runnable"))
        XCTAssertLessThan(output.optimizedPrompt.count, 1_500)
    }

    func testGrokJSONStructuredIncludesJSONContractAndWarnings() {
        let output = optimizer.optimize(
            OptimizationInput(
                rawUserPrompt: "Return deployment metadata for services as structured output.",
                modelFamily: .xAIGrokStyle,
                scenario: .jsonStructuredOutput,
                userOverrides: nil
            )
        )

        XCTAssertTrue(output.optimizedPrompt.localizedCaseInsensitiveContains("json"))
        XCTAssertTrue(output.optimizedPrompt.localizedCaseInsensitiveContains("no markdown"))
        XCTAssertFalse(output.warnings.isEmpty)
    }

    func testOpenAIIDEProducesPatchFriendlyScaffold() {
        let output = optimizer.optimize(
            OptimizationInput(
                rawUserPrompt: "Fix flaky auth test and provide a minimal patch.",
                modelFamily: .openAIGPTStyle,
                scenario: .ideCodingAssistant,
                userOverrides: nil
            )
        )

        XCTAssertTrue(output.optimizedPrompt.contains("Unified Diff"))
        XCTAssertTrue(output.optimizedPrompt.contains("Tests"))
        XCTAssertTrue(output.appliedRules.contains(where: { $0.localizedCaseInsensitiveContains("patch") }))
    }
}
