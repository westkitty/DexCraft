import Foundation
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

    func testSafetyPreservesFencedCodePathURLAndPlaceholder() {
        let input = """
        Improve this prompt maybe for {project_name}.
        Keep /Users/name/Project/file.swift and https://example.com/api unchanged.

        ```swift
        let url = "https://example.com/api"
        let path = "/Users/name/Project/file.swift"
        let variable = "{project_name}"
        ```
        """

        let result = HeuristicPromptOptimizer.optimize(input)

        XCTAssertTrue(result.optimizedText.contains("{project_name}"))
        XCTAssertTrue(result.optimizedText.contains("/Users/name/Project/file.swift"))
        XCTAssertTrue(result.optimizedText.contains("https://example.com/api"))
        XCTAssertTrue(result.optimizedText.contains("""
        ```swift
        let url = "https://example.com/api"
        let path = "/Users/name/Project/file.swift"
        let variable = "{project_name}"
        ```
        """))
    }

    func testGapDrivenWeakPromptGetsMissingSectionsInserted() {
        let result = HeuristicPromptOptimizer.optimize(
            "Improve this maybe",
            context: HeuristicOptimizationContext(target: .claude, scenario: .generalAssistant)
        )

        XCTAssertTrue(result.optimizedText.contains("### Deliverables"))
        XCTAssertTrue(result.optimizedText.contains("### Output Format"))
        XCTAssertTrue(result.optimizedText.contains("### Success Criteria"))
        XCTAssertTrue(result.optimizedText.contains("### Questions"))
    }

    func testUnderspecifiedBuildTaskGetsStructuralExpansion() {
        let result = HeuristicPromptOptimizer.optimize(
            "Build me a chess game.",
            context: HeuristicOptimizationContext(target: .claude, scenario: .generalAssistant)
        )

        XCTAssertTrue(result.optimizedText.contains("### Constraints"))
        XCTAssertTrue(result.optimizedText.contains("### Output Format"))
        XCTAssertTrue(result.optimizedText.contains("### Success Criteria"))
        XCTAssertTrue(result.optimizedText.contains("### Questions"))
    }

    func testGapDrivenStrongPromptAvoidsUnnecessaryExpansion() {
        let baseline = """
        ### Goal
        Produce a concise implementation plan.

        ### Constraints
        - Keep behavior deterministic.
        - Preserve fenced code blocks and placeholders exactly.

        ### Deliverables
        1. Ordered implementation plan.
        2. Patch summary.
        3. Validation checklist.

        ### Output Format
        Use markdown headings: Plan, Patch Summary, Validation.

        ### Success Criteria
        - Every required section is present.
        - Instructions are testable and unambiguous.
        """

        let result = HeuristicPromptOptimizer.optimize(
            baseline,
            context: HeuristicOptimizationContext(target: .claude, scenario: .generalAssistant)
        )

        XCTAssertEqual(result.optimizedText, baseline)
        XCTAssertEqual(result.selectedCandidateTitle, "0 Baseline")
    }

    func testAntiRegressionKeepsStructuredBaselineWithoutMeaningfulGain() {
        let baseline = """
        ### Goal
        Refine the prompt format.

        ### Context
        Existing prompt already has strict structure.

        ### Constraints
        - Keep output deterministic.
        - Keep the response concise.

        ### Deliverables
        1. Structured output.
        2. Validation notes.
        3. No unnecessary expansion.

        ### Output Format
        Use markdown sections with numbered deliverables.

        ### Questions
        - None.

        ### Success Criteria
        - No regressions.
        - No structural drift.
        """

        let result = HeuristicPromptOptimizer.optimize(
            baseline,
            context: HeuristicOptimizationContext(target: .geminiChatGPT, scenario: .generalAssistant)
        )

        XCTAssertEqual(result.optimizedText, baseline)
        XCTAssertTrue(result.warnings.contains(where: { $0.localizedCaseInsensitiveContains("Anti-regression fallback") }) || result.selectedCandidateTitle == "0 Baseline")
    }

    func testContradictionRepairRewritesKnownConflictsDeterministically() {
        let input = """
        Be concise but exhaustive.
        No browsing.
        Also browse the web for supporting research.
        No code, but implement the patch.
        """

        let result = HeuristicPromptOptimizer.optimize(
            input,
            context: HeuristicOptimizationContext(target: .claude, scenario: .generalAssistant)
        )

        XCTAssertFalse(result.optimizedText.localizedCaseInsensitiveContains("browse the web"))
        XCTAssertTrue(result.optimizedText.localizedCaseInsensitiveContains("provided/local sources only"))
        XCTAssertTrue(result.optimizedText.localizedCaseInsensitiveContains("non-code implementation plan"))
    }

    func testSentenceRewriteOnlyMutatesNonCodeSegments() {
        let input = """
        maybe improve this and try to make it better.

        ```bash
        echo "maybe keep this exact"
        ```
        """

        let result = HeuristicPromptOptimizer.optimize(input)

        XCTAssertFalse(result.optimizedText.lowercased().contains("maybe improve this"))
        XCTAssertTrue(result.optimizedText.contains("echo \"maybe keep this exact\""))
    }

    func testDomainPacksByScenarioInjectExpectedPolicies() {
        let expectations: [(ScenarioProfile, String)] = [
            (.generalAssistant, "deterministic"),
            (.ideCodingAssistant, "Unified Diff"),
            (.cliAssistant, "shell commands only"),
            (.jsonStructuredOutput, "Return JSON only"),
            (.longformWriting, "narrative continuity"),
            (.researchSummarization, "Citations"),
            (.toolUsingAgent, "Tool Calls")
        ]

        for (scenario, needle) in expectations {
            let result = HeuristicPromptOptimizer.optimize(
                "make this better maybe",
                context: HeuristicOptimizationContext(target: .claude, scenario: scenario)
            )
            XCTAssertTrue(
                result.optimizedText.localizedCaseInsensitiveContains(needle),
                "Expected scenario \(scenario.rawValue) to include '\(needle)'."
            )
        }
    }

    func testDomainPacksByTargetInjectExpectedPolicies() {
        let expectations: [(PromptTarget, [String])] = [
            (.claude, ["### Goal"]),
            (.geminiChatGPT, ["### Goal"]),
            (.perplexity, ["primary sources", "URL"]),
            (.agenticIDE, ["Proposed File Changes", "Validation Commands"])
        ]

        for (target, needles) in expectations {
            let result = HeuristicPromptOptimizer.optimize(
                "improve this maybe",
                context: HeuristicOptimizationContext(target: target, scenario: .generalAssistant)
            )
            for needle in needles {
                XCTAssertTrue(
                    result.optimizedText.localizedCaseInsensitiveContains(needle),
                    "Expected target \(target.rawValue) to include '\(needle)'."
                )
            }
        }
    }

    func testQualityGateAddsRequiredSectionsForAmbiguousPrompt() {
        let result = HeuristicPromptOptimizer.optimize(
            "maybe make it better",
            context: HeuristicOptimizationContext(target: .claude, scenario: .toolUsingAgent)
        )

        XCTAssertTrue(result.optimizedText.contains("### Goal"))
        XCTAssertTrue(result.optimizedText.contains("### Constraints"))
        XCTAssertTrue(result.optimizedText.contains("### Deliverables"))
        XCTAssertTrue(result.optimizedText.contains("### Output Format"))
        XCTAssertTrue(result.optimizedText.contains("### Success Criteria"))
    }

    func testDeterministicRepeatedRunsProduceIdenticalOutput() {
        let input = "Improve this maybe while keeping /Users/name/repo and {placeholder}."
        let context = HeuristicOptimizationContext(target: .agenticIDE, scenario: .ideCodingAssistant)

        let first = HeuristicPromptOptimizer.optimize(input, context: context)

        for _ in 0..<20 {
            let next = HeuristicPromptOptimizer.optimize(input, context: context)
            XCTAssertEqual(next.optimizedText, first.optimizedText)
            XCTAssertEqual(next.selectedCandidateTitle, first.selectedCandidateTitle)
            XCTAssertEqual(next.score, first.score)
        }
    }

    func testPerformanceSanityRepeatedRunsUnderBudget() {
        let input = "Improve this maybe and include output structure for a coding task."
        let context = HeuristicOptimizationContext(target: .agenticIDE, scenario: .ideCodingAssistant)

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<500 {
            _ = HeuristicPromptOptimizer.optimize(input, context: context)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 3.0, "Expected repeated optimizer runs to stay under 3 seconds.")
    }

    func testLearnWeightsFromHistoryProvidesBoundedWeights() {
        let history = (0..<8).map { _ in
            "Improve this maybe and keep it brief."
        }

        guard let tuned = HeuristicPromptOptimizer.learnWeights(from: history) else {
            return XCTFail("Expected learned weights for sufficient history.")
        }

        let clamped = tuned.clamped()
        XCTAssertEqual(tuned, clamped)
        XCTAssertGreaterThanOrEqual(tuned.outputFormat, 5)
        XCTAssertLessThanOrEqual(tuned.outputFormat, 30)
        XCTAssertLessThanOrEqual(tuned.tokenPenaltyBase, -2)
        XCTAssertGreaterThanOrEqual(tuned.tokenPenaltyBase, -22)
    }
}
