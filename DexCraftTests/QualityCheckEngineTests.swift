import XCTest

final class QualityCheckEngineTests: XCTestCase {
    private let engine = QualityCheckEngine()

    private let baseContext = PromptBuildContext(
        goal: "Refactor PromptEngineViewModel into modular services",
        context: "DexCraft is a SwiftUI macOS app. Keep it offline.",
        constraints: ["No networking", "Add unit tests", "Deterministic output"],
        deliverables: ["New services", "Updated ViewModel", "Tests passing"],
        variables: ["app": "DexCraft"]
    )

    private let allSections = PromptSectionsConfig(
        includeGoal: true,
        includeContext: true,
        includeConstraints: true,
        includeDeliverables: true
    )

    private let resolvedVariables = VariableResolutionResult(
        detected: ["app"],
        resolvedText: "DexCraft",
        unfilled: []
    )

    private let longEnoughPrompt = String(repeating: "x", count: 220)

    func testMissingGoal() {
        let ctx = PromptBuildContext(
            goal: "",
            context: baseContext.context,
            constraints: baseContext.constraints,
            deliverables: baseContext.deliverables,
            variables: baseContext.variables
        )

        let checks = engine.evaluate(
            ctx: ctx,
            sections: allSections,
            variableResult: resolvedVariables,
            generatedPrompt: longEnoughPrompt
        )

        guard let goalCheck = checks.first(where: { $0.title.localizedCaseInsensitiveContains("goal") }) else {
            return XCTFail("Expected goal check.")
        }

        XCTAssertFalse(goalCheck.passed)
        XCTAssertEqual(goalCheck.severity, .error)
    }

    func testMissingVariables() {
        let variableResult = VariableResolutionResult(
            detected: ["name"],
            resolvedText: "Hello {name}",
            unfilled: ["name"]
        )

        let checks = engine.evaluate(
            ctx: baseContext,
            sections: allSections,
            variableResult: variableResult,
            generatedPrompt: longEnoughPrompt
        )

        guard let variableCheck = checks.first(where: { $0.title.localizedCaseInsensitiveContains("variable") }) else {
            return XCTFail("Expected variable check.")
        }

        XCTAssertFalse(variableCheck.passed)
        XCTAssertEqual(variableCheck.severity, .error)
        XCTAssertTrue(variableCheck.detail?.contains("name") == true)
    }

    func testConstraintsEnabledButEmpty() {
        let ctx = PromptBuildContext(
            goal: baseContext.goal,
            context: baseContext.context,
            constraints: [],
            deliverables: baseContext.deliverables,
            variables: baseContext.variables
        )

        let checks = engine.evaluate(
            ctx: ctx,
            sections: allSections,
            variableResult: resolvedVariables,
            generatedPrompt: longEnoughPrompt
        )

        guard let constraintsCheck = checks.first(where: { $0.title.localizedCaseInsensitiveContains("constraints") }) else {
            return XCTFail("Expected constraints check.")
        }

        XCTAssertFalse(constraintsCheck.passed)
        XCTAssertEqual(constraintsCheck.severity, .warning)
    }

    func testOutputTooShort() {
        let checks = engine.evaluate(
            ctx: baseContext,
            sections: allSections,
            variableResult: resolvedVariables,
            generatedPrompt: "hi"
        )

        guard let outputCheck = checks.first(where: { $0.title.localizedCaseInsensitiveContains("output size") }) else {
            return XCTFail("Expected output size check.")
        }

        XCTAssertFalse(outputCheck.passed)
        XCTAssertEqual(outputCheck.severity, .warning)
    }
}
