import XCTest

final class PromptRestructurerTests: XCTestCase {
    func testSingleParagraphDoesNotMirrorFullInputAsContext() {
        let input = "Implement deterministic prompt restructuring for DexCraft."

        let structured = PromptRestructurer.restructure(
            input,
            selectedTarget: .geminiChatGPT,
            options: EnhancementOptions()
        )

        XCTAssertNotEqual(
            structured.context.trimmingCharacters(in: .whitespacesAndNewlines),
            input.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testRunOnDictationBuildsRequirementsBucket() {
        let input = "I would like to simplify prompt generation and we need to normalize sections; it is important that output stays deterministic."

        let structured = PromptRestructurer.restructure(
            input,
            selectedTarget: .geminiChatGPT,
            options: EnhancementOptions()
        )

        XCTAssertFalse(structured.requirements.isEmpty)
    }

    func testClaudeOutputIncludesStructuredXMLTags() {
        let output = PromptFormattingEngine.buildPrompt(
            input: "We need to normalize prompt sections. Must remain offline-only. Provide clear deliverables.",
            target: .claude,
            options: EnhancementOptions(),
            connectedModelSettings: ConnectedModelSettings()
        )

        XCTAssertTrue(output.contains("<objective>"))
        XCTAssertTrue(output.contains("<context>"))
        XCTAssertTrue(output.contains("<requirements>"))
        XCTAssertTrue(output.contains("<constraints>"))
        XCTAssertTrue(output.contains("<deliverables>"))
    }

    func testAgenticOutputIncludesOrderedScaffoldAndRequirementBullets() {
        let output = PromptFormattingEngine.buildPrompt(
            input: "I would like to add deterministic restructuring. We need tests. Must not use network calls. Provide validation commands.",
            target: .agenticIDE,
            options: EnhancementOptions(),
            connectedModelSettings: ConnectedModelSettings()
        )

        XCTAssertTrue(output.contains("### Requirements\n- "))

        let expectedHeadings = [
            "### Goal",
            "### Context",
            "### Requirements",
            "### Constraints",
            "### Deliverables",
            "### Plan",
            "### Unified Diff",
            "### Tests",
            "### Validation"
        ]

        var searchRange = output.startIndex..<output.endIndex
        for heading in expectedHeadings {
            guard let range = output.range(of: heading, options: [], range: searchRange) else {
                return XCTFail("Missing heading: \(heading)")
            }
            searchRange = range.upperBound..<output.endIndex
        }
    }
}
