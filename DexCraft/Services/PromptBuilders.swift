import Foundation

struct PromptBuildContext: Codable, Equatable {
    let goal: String
    let context: String
    let constraints: [String]
    let deliverables: [String]
    let variables: [String: String]
}

struct PromptSectionsConfig: Equatable {
    let includeGoal: Bool
    let includeContext: Bool
    let includeConstraints: Bool
    let includeDeliverables: Bool
}

protocol PromptBuilder {
    func build(ctx: PromptBuildContext, sections: PromptSectionsConfig) -> String
}

struct ClaudeBuilder: PromptBuilder {
    func build(ctx: PromptBuildContext, sections: PromptSectionsConfig) -> String {
        PromptBuilderRenderer.render(
            ctx: ctx,
            sections: sections,
            labels: .init(
                goal: "Goal:",
                context: "Context:",
                constraints: "Constraints:",
                deliverables: "Deliverables:",
                variables: "Variables:"
            )
        )
    }
}

struct GeminiBuilder: PromptBuilder {
    func build(ctx: PromptBuildContext, sections: PromptSectionsConfig) -> String {
        PromptBuilderRenderer.render(
            ctx: ctx,
            sections: sections,
            labels: .init(
                goal: "Objective:",
                context: "Project Context:",
                constraints: "Hard Constraints:",
                deliverables: "Expected Deliverables:",
                variables: "Template Variables:"
            )
        )
    }
}

struct PerplexityBuilder: PromptBuilder {
    func build(ctx: PromptBuildContext, sections: PromptSectionsConfig) -> String {
        PromptBuilderRenderer.render(
            ctx: ctx,
            sections: sections,
            labels: .init(
                goal: "Research Goal:",
                context: "Background Context:",
                constraints: "Constraints:",
                deliverables: "Deliverables:",
                variables: "Variables:"
            )
        )
    }
}

struct AgenticIDEBuilder: PromptBuilder {
    func build(ctx: PromptBuildContext, sections: PromptSectionsConfig) -> String {
        PromptBuilderRenderer.render(
            ctx: ctx,
            sections: sections,
            labels: .init(
                goal: "Task Goal:",
                context: "Repository Context:",
                constraints: "Execution Constraints:",
                deliverables: "Implementation Deliverables:",
                variables: "Variables:"
            )
        )
    }
}

struct PromptBuilderRegistry {
    private let builders: [PromptTarget: PromptBuilder]

    init(builders: [PromptTarget: PromptBuilder]? = nil) {
        if let builders {
            self.builders = builders
            return
        }

        self.builders = [
            .claude: ClaudeBuilder(),
            .geminiChatGPT: GeminiBuilder(),
            .perplexity: PerplexityBuilder(),
            .agenticIDE: AgenticIDEBuilder()
        ]
    }

    func builder(for target: PromptTarget) -> PromptBuilder? {
        builders[target]
    }
}

private struct BuilderLabels {
    let goal: String
    let context: String
    let constraints: String
    let deliverables: String
    let variables: String
}

private enum PromptBuilderRenderer {
    static func render(
        ctx: PromptBuildContext,
        sections: PromptSectionsConfig,
        labels: BuilderLabels
    ) -> String {
        let goalOnlyMode = sections.includeGoal &&
            !sections.includeContext &&
            !sections.includeConstraints &&
            !sections.includeDeliverables

        var blocks: [String] = []

        if sections.includeGoal {
            let goal = clean(ctx.goal)
            if !goal.isEmpty {
                blocks.append("\(labels.goal)\n\(goal)")
            }
        }

        if sections.includeContext {
            let context = clean(ctx.context)
            if !context.isEmpty {
                blocks.append("\(labels.context)\n\(context)")
            }
        }

        if sections.includeConstraints {
            let constraints = cleanList(ctx.constraints)
            if !constraints.isEmpty {
                blocks.append("\(labels.constraints)\n\(bulletize(constraints))")
            }
        }

        if sections.includeDeliverables {
            let deliverables = cleanList(ctx.deliverables)
            if !deliverables.isEmpty {
                blocks.append("\(labels.deliverables)\n\(bulletize(deliverables))")
            }
        }

        let variableLines = cleanVariables(ctx.variables)
        if !goalOnlyMode, !variableLines.isEmpty {
            blocks.append("\(labels.variables)\n\(bulletize(variableLines))")
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanList(_ values: [String]) -> [String] {
        values.map(clean).filter { !$0.isEmpty }
    }

    private static func cleanVariables(_ values: [String: String]) -> [String] {
        values
            .map { key, value in
                (clean(key), clean(value))
            }
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }
            .sorted {
                let lhs = $0.0.lowercased()
                let rhs = $1.0.lowercased()
                if lhs == rhs {
                    return $0.0 < $1.0
                }
                return lhs < rhs
            }
            .map { "\($0.0): \($0.1)" }
    }

    private static func bulletize(_ values: [String]) -> String {
        values.map { "- \($0)" }.joined(separator: "\n")
    }
}
