import XCTest

final class PromptSectionsConfigTests: XCTestCase {
    private let ctx = PromptBuildContext(
        goal: "Refactor PromptEngineViewModel into modular services",
        context: "DexCraft is a SwiftUI macOS app. Keep it offline.",
        constraints: ["No networking", "Add unit tests", "Deterministic output"],
        deliverables: ["New services", "Updated ViewModel", "Tests passing"],
        variables: ["app": "DexCraft"]
    )

    private struct Fixture {
        let builder: PromptBuilder
        let goalHeading: String
        let constraintsHeading: String
        let deliverablesHeading: String
    }

    private let fixtures: [Fixture] = [
        Fixture(
            builder: ClaudeBuilder(),
            goalHeading: "Goal:",
            constraintsHeading: "Constraints:",
            deliverablesHeading: "Deliverables:"
        ),
        Fixture(
            builder: GeminiBuilder(),
            goalHeading: "Objective:",
            constraintsHeading: "Hard Constraints:",
            deliverablesHeading: "Expected Deliverables:"
        ),
        Fixture(
            builder: PerplexityBuilder(),
            goalHeading: "Research Goal:",
            constraintsHeading: "Constraints:",
            deliverablesHeading: "Deliverables:"
        ),
        Fixture(
            builder: AgenticIDEBuilder(),
            goalHeading: "Task Goal:",
            constraintsHeading: "Execution Constraints:",
            deliverablesHeading: "Implementation Deliverables:"
        )
    ]

    func testExcludeConstraints() {
        let sections = PromptSectionsConfig(
            includeGoal: true,
            includeContext: true,
            includeConstraints: false,
            includeDeliverables: true
        )

        for fixture in fixtures {
            let output = fixture.builder.build(ctx: ctx, sections: sections)
            XCTAssertFalse(output.contains("No networking"))
            XCTAssertFalse(output.contains(fixture.constraintsHeading))
        }
    }

    func testExcludeDeliverables() {
        let sections = PromptSectionsConfig(
            includeGoal: true,
            includeContext: true,
            includeConstraints: true,
            includeDeliverables: false
        )

        for fixture in fixtures {
            let output = fixture.builder.build(ctx: ctx, sections: sections)
            XCTAssertFalse(output.contains("Tests passing"))
            XCTAssertFalse(output.contains(fixture.deliverablesHeading))
        }
    }

    func testOnlyGoal() {
        let sections = PromptSectionsConfig(
            includeGoal: true,
            includeContext: false,
            includeConstraints: false,
            includeDeliverables: false
        )

        for fixture in fixtures {
            let output = fixture.builder.build(ctx: ctx, sections: sections)
            XCTAssertEqual(output, "\(fixture.goalHeading)\n\(ctx.goal)")
            XCTAssertFalse(output.contains(ctx.context))
            XCTAssertFalse(output.contains("No networking"))
            XCTAssertFalse(output.contains("Tests passing"))
        }
    }
}
