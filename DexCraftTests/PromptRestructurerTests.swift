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

    func testGeminiOutputStartsWithNoFillerPreamble() {
        let output = PromptFormattingEngine.buildPrompt(
            input: "Create a card-based app for daily planning with tasks and goals.",
            target: .geminiChatGPT,
            options: EnhancementOptions(),
            connectedModelSettings: ConnectedModelSettings()
        )

        let firstLine = output
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(firstLine, "Respond only with the requested output. Do not apologize or use conversational filler.")
    }

    func testAgenticOutputIncludesSystemRulesAndOperationalSections() {
        let output = PromptFormattingEngine.buildPrompt(
            input: "Implement deterministic offline prompt generation with clear build and validation commands.",
            target: .agenticIDE,
            options: EnhancementOptions(),
            connectedModelSettings: ConnectedModelSettings()
        )

        XCTAssertTrue(output.contains("# DexCraft Agentic System Rules"))
        XCTAssertTrue(output.contains("### File Tree Request"))
        XCTAssertTrue(output.contains("### Build/Run Commands"))
        XCTAssertTrue(output.contains("### Git/Revert Plan"))
        XCTAssertTrue(output.contains("### Implementation Style"))
    }

    func testFormatterReflectsFileTreeAndVerificationToggleConstraints() {
        var options = makeAllDisabledOptions()
        options.addFileTreeRequest = true
        let fileTreeOutput = PromptFormattingEngine.buildPrompt(
            input: "Build a local planner app.",
            target: .geminiChatGPT,
            options: options,
            connectedModelSettings: ConnectedModelSettings()
        )

        XCTAssertTrue(fileTreeOutput.contains("Include a File Tree Request section before implementation details."))
        XCTAssertFalse(fileTreeOutput.contains("Include a deterministic Verification Checklist section tied to requirements."))

        options = makeAllDisabledOptions()
        options.includeVerificationChecklist = true
        let verificationOutput = PromptFormattingEngine.buildPrompt(
            input: "Build a local planner app.",
            target: .geminiChatGPT,
            options: options,
            connectedModelSettings: ConnectedModelSettings()
        )

        XCTAssertFalse(verificationOutput.contains("Include a File Tree Request section before implementation details."))
        XCTAssertTrue(verificationOutput.contains("Include a deterministic Verification Checklist section tied to requirements."))
    }

    private func makeAllDisabledOptions() -> EnhancementOptions {
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
        return options
    }
}
