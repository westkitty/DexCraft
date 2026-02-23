import XCTest

final class PromptBuilderTests: XCTestCase {
    private let ctx = PromptBuildContext(
        goal: "Refactor PromptEngineViewModel into modular services",
        context: "DexCraft is a SwiftUI macOS app. Keep it offline.",
        constraints: ["No networking", "Add unit tests", "Deterministic output"],
        deliverables: ["New services", "Updated ViewModel", "Tests passing"],
        variables: ["app": "DexCraft"]
    )

    private let sections = PromptSectionsConfig(
        includeGoal: true,
        includeContext: true,
        includeConstraints: true,
        includeDeliverables: true
    )

    func testDeterminismPerBuilder() {
        let builders: [PromptBuilder] = [
            ClaudeBuilder(),
            GeminiBuilder(),
            PerplexityBuilder(),
            AgenticIDEBuilder()
        ]

        for builder in builders {
            let first = builder.build(ctx: ctx, sections: sections)
            let second = builder.build(ctx: ctx, sections: sections)
            XCTAssertEqual(first, second)
        }
    }

    func testContainsCoreContent() {
        let builders: [PromptBuilder] = [
            ClaudeBuilder(),
            GeminiBuilder(),
            PerplexityBuilder(),
            AgenticIDEBuilder()
        ]

        for builder in builders {
            let output = builder.build(ctx: ctx, sections: sections)
            XCTAssertTrue(output.contains(ctx.goal))
            XCTAssertTrue(output.contains("No networking"))
            XCTAssertTrue(output.contains("Tests passing"))
        }
    }

    func testRegistryWorks() {
        let registry = PromptBuilderRegistry()
        let targets: [PromptTarget] = [.claude, .geminiChatGPT, .perplexity, .agenticIDE]

        for target in targets {
            let builder = registry.builder(for: target)
            XCTAssertNotNil(builder)
            let output = builder?.build(ctx: ctx, sections: sections) ?? ""
            XCTAssertFalse(output.isEmpty)
        }
    }
}
