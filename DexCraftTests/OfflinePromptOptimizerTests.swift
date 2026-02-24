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

    func testPromptTextGuardsPreserveFencedCodeExactly() {
        let input = """
        Intro line
        ```swift
        let url = "https://example.com/api"
        let path = "/Users/name/Project/file.swift"
        ```
        Outro line
        """

        let segments = PromptTextGuards.splitByCodeFences(input)
        let rebuilt = PromptTextGuards.transformTextSegments(segments) { text in
            text.replacingOccurrences(of: "line", with: "sentence")
        }

        XCTAssertTrue(rebuilt.contains("""
        ```swift
        let url = "https://example.com/api"
        let path = "/Users/name/Project/file.swift"
        ```
        """))
        XCTAssertTrue(rebuilt.contains("Intro sentence"))
        XCTAssertTrue(rebuilt.contains("Outro sentence"))
    }

    func testHeuristicOptimizerPreservesCodePathsAndURLs() {
        let input = """
        Improve this prompt maybe.

        ```bash
        cat /Users/name/Project/file.swift
        curl https://example.com/endpoint
        ```

        Also include /Users/name/Project/file.swift and https://example.com/endpoint in the final instructions.
        """

        let result = HeuristicPromptOptimizer.optimize(input)

        XCTAssertTrue(result.optimizedText.contains("""
        ```bash
        cat /Users/name/Project/file.swift
        curl https://example.com/endpoint
        ```
        """))
        XCTAssertTrue(result.optimizedText.contains("/Users/name/Project/file.swift"))
        XCTAssertTrue(result.optimizedText.contains("https://example.com/endpoint"))
    }

    func testHeuristicOptimizerPreservesVariablePlaceholders() {
        let input = "Improve this prompt for {project_name} and maybe include {target_file}."
        let result = HeuristicPromptOptimizer.optimize(input)
        XCTAssertTrue(result.optimizedText.contains("{project_name}"))
        XCTAssertTrue(result.optimizedText.contains("{target_file}"))
    }

    func testHeuristicOptimizerAddsStructureForVagueInput() {
        let result = HeuristicPromptOptimizer.optimize("Improve this prompt")

        XCTAssertTrue(result.optimizedText.contains("### Deliverables"))
        XCTAssertTrue(result.optimizedText.contains("### Output Format"))
        XCTAssertTrue(result.optimizedText.contains("### Success Criteria"))
        XCTAssertTrue(result.optimizedText.contains("### Questions"))
    }

    func testHeuristicOptimizerAntiRegressionKeepsStrongBaseline() {
        let baseline = """
        ### Goal
        Produce a concise implementation plan.

        ### Context
        Existing architecture is modular and tests are present.

        ### Constraints
        - Must stay offline.
        - Must not change API contracts.
        - Only modify required files.

        ### Deliverables
        1. Ordered plan.
        2. Patch summary.
        3. Validation checklist.

        ### Output Format
        Use markdown with sections: Plan, Patch Summary, Validation.

        ### Questions
        - None.

        ### Success Criteria
        - All requested sections are present.
        - Steps are deterministic.
        """

        let result = HeuristicPromptOptimizer.optimize(baseline)
        XCTAssertEqual(result.optimizedText, baseline)
    }

    func testHeuristicOptimizerDeHedgePreservesIndentedMarkdown() {
        let input = """
        ### Output Format
        1. Main Item
           - maybe nested detail
        """

        let result = HeuristicPromptOptimizer.optimize(input)
        XCTAssertTrue(result.optimizedText.contains("   - "))
    }
}
