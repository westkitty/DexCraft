import Foundation

enum PromptFormattingEngine {
    private static let noFillerConstraint = "Respond only with the requested output. Do not apologize or use conversational filler."
    private static let markdownConstraint = "Use strict markdown structure and headings exactly as specified."
    private static let strictCodeConstraint = "Output strict code or configuration only when code is requested."

    static func buildPrompt(
        input: String,
        target: PromptTarget,
        options: EnhancementOptions,
        connectedModelSettings: ConnectedModelSettings
    ) -> String {
        let profile = PromptProfile.profile(for: target, settings: connectedModelSettings)
        let structured = PromptRestructurer.restructure(
            input,
            selectedTarget: target,
            options: options
        )
        let constraints = dedupePreservingOrder(
            structured.constraints + buildConstraintLines(target: target, options: options)
        )
        let deliverables = dedupePreservingOrder(
            structured.deliverables + buildDeliverablesLines(target: target)
        )
        let context = contextForTarget(profile: profile, baseContext: structured.context, requirements: structured.requirements)

        switch target {
        case .claude:
            return buildClaudePrompt(
                goal: structured.goal,
                context: context,
                requirements: structured.requirements,
                constraints: constraints,
                deliverables: deliverables,
                profile: profile
            )
        case .agenticIDE:
            return buildAgenticIDEPrompt(
                goal: structured.goal,
                context: context,
                requirements: structured.requirements,
                constraints: constraints,
                deliverables: deliverables,
                profile: profile
            )
        case .perplexity:
            return buildPerplexityPrompt(
                goal: structured.goal,
                context: context,
                requirements: structured.requirements,
                constraints: constraints,
                deliverables: deliverables,
                profile: profile
            )
        case .geminiChatGPT:
            return buildGeminiChatGPTPrompt(
                goal: structured.goal,
                context: context,
                requirements: structured.requirements,
                constraints: constraints,
                deliverables: deliverables,
                profile: profile,
                options: options
            )
        }
    }

    private static func contextForTarget(profile: PromptProfile, baseContext: String, requirements: [String]) -> String {
        guard !requirements.isEmpty else { return baseContext }

        switch profile.formatStyle {
        case .claudeXML, .markdownHeadings, .agenticIDE, .perplexitySearch:
            return baseContext
        }
    }

    private static func dedupePreservingOrder(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for line in lines {
            let key = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                output.append(key)
            }
        }

        return output
    }

    private static func buildConstraintLines(target: PromptTarget, options: EnhancementOptions) -> [String] {
        dedupePreservingOrder(optionConstraintLines(options: options) + targetConstraintLines(for: target))
    }

    private static func buildDeliverablesLines(target: PromptTarget) -> [String] {
        switch target {
        case .claude, .geminiChatGPT, .perplexity, .agenticIDE:
            return [
                "Complete every requested deliverable with concrete output.",
                "Call out assumptions before implementation details."
            ]
        }
    }

    private static func optionConstraintLines(options: EnhancementOptions) -> [String] {
        var lines: [String] = []

        if options.noConversationalFiller {
            lines.append(noFillerConstraint)
        }

        if options.enforceMarkdown {
            lines.append(markdownConstraint)
        }

        if options.strictCodeOnly {
            lines.append(strictCodeConstraint)
        }

        return lines
    }

    private static func targetConstraintLines(for target: PromptTarget) -> [String] {
        switch target {
        case .claude:
            return ["Optimize structure for direct consumption by Claude."]
        case .geminiChatGPT:
            return ["Use strict markdown hierarchy with concise, actionable language."]
        case .perplexity:
            return ["Optimize for search-grounded synthesis with explicit verification."]
        case .agenticIDE:
            return ["Use deterministic file-writing instructions with explicit command order."]
        }
    }

    private static func buildClaudePrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile
    ) -> String {
        var sections: [String] = []

        sections.append("<provider>\(profile.provider)</provider>")
        sections.append("<connected_model>\(connectedModelLabel(for: profile))</connected_model>")
        sections.append("<system_preamble>\n\(bulletize(profile.defaultSystemPreambleLines))\n</system_preamble>")
        sections.append("<objective>\n\(goal)\n</objective>")
        sections.append("<context>\n\(context.isEmpty ? "No additional context provided." : context)\n</context>")

        if !requirements.isEmpty {
            sections.append("<requirements>\n\(bulletize(requirements))\n</requirements>")
        }

        sections.append("<constraints>\n\(bulletize(constraints))\n</constraints>")
        sections.append("<deliverables>\n\(bulletize(deliverables))\n</deliverables>")
        sections.append("<output_contract>\n\(bulletize(profile.outputContractLines))\n</output_contract>")
        sections.append("<pitfalls_to_avoid>\n\(bulletize(profile.pitfallsAvoidLines))\n</pitfalls_to_avoid>")
        sections.append("<tactics>\n\(bulletize(profile.tacticsLines))\n</tactics>")

        return sections.joined(separator: "\n\n")
    }

    private static func buildAgenticIDEPrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile
    ) -> String {
        var sections: [String] = []

        sections.append(section(title: "Provider", body: profile.provider))
        sections.append(section(title: "Connected Model", body: connectedModelLabel(for: profile)))
        sections.append(section(title: "System Preamble", body: bulletize(profile.defaultSystemPreambleLines)))
        sections.append(section(title: "Goal", body: goal))
        sections.append(section(title: "Context", body: context.isEmpty ? "No additional context provided." : context))

        if !requirements.isEmpty {
            sections.append(section(title: "Requirements", body: bulletize(requirements)))
        }

        sections.append(section(title: "Constraints", body: bulletize(constraints)))
        sections.append(section(title: "Deliverables", body: bulletize(deliverables)))
        sections.append(section(title: "Plan", body: bulletize(profile.tacticsLines)))
        sections.append(section(title: "Unified Diff", body: "- Provide a concise, file-scoped unified diff summary."))
        sections.append(section(title: "Tests", body: "- List deterministic test cases and expected outcomes."))
        sections.append(section(title: "Validation", body: bulletize(profile.outputContractLines)))
        sections.append(section(title: "Build/Run Commands", body: "- List commands in execution order."))
        sections.append(section(title: "Git/Revert Plan", body: bulletize(profile.pitfallsAvoidLines)))

        return sections.joined(separator: "\n\n")
    }

    private static func buildPerplexityPrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile
    ) -> String {
        var sections: [String] = []

        sections.append(section(title: "Provider", body: profile.provider))
        sections.append(section(title: "Connected Model", body: connectedModelLabel(for: profile)))
        sections.append(section(title: "System Preamble", body: bulletize(profile.defaultSystemPreambleLines)))
        sections.append(section(title: "Goal", body: goal))
        sections.append(section(title: "Context", body: context.isEmpty ? "No additional context provided." : context))

        if !requirements.isEmpty {
            sections.append(section(title: "Requirements", body: bulletize(requirements)))
        }

        sections.append(section(title: "Constraints", body: bulletize(constraints)))
        sections.append(section(title: "Deliverables", body: bulletize(deliverables)))
        sections.append(
            section(
                title: "Search & Verification Requirements",
                body: bulletize([
                    "Search for primary sources before final synthesis.",
                    "Cite sources inline as markdown links for factual claims.",
                    "If evidence conflicts, summarize the conflict and confidence."
                ])
            )
        )
        sections.append(section(title: "Output Contract", body: bulletize(profile.outputContractLines)))
        sections.append(section(title: "Pitfalls to Avoid", body: bulletize(profile.pitfallsAvoidLines)))
        sections.append(section(title: "Tactics", body: bulletize(profile.tacticsLines)))

        return sections.joined(separator: "\n\n")
    }

    private static func buildGeminiChatGPTPrompt(
        goal: String,
        context: String,
        requirements: [String],
        constraints: [String],
        deliverables: [String],
        profile: PromptProfile,
        options: EnhancementOptions
    ) -> String {
        var outputContractLines = profile.outputContractLines
        if options.noConversationalFiller {
            outputContractLines.append("Respond only with the requested sections.")
        }

        var sections: [String] = []
        sections.append(section(title: "Provider", body: profile.provider))
        sections.append(section(title: "Connected Model", body: connectedModelLabel(for: profile)))
        sections.append(section(title: "System Preamble", body: bulletize(profile.defaultSystemPreambleLines)))
        sections.append(section(title: "Goal", body: goal))
        sections.append(section(title: "Context", body: context.isEmpty ? "No additional context provided." : context))

        if !requirements.isEmpty {
            sections.append(section(title: "Requirements", body: bulletize(requirements)))
        }

        sections.append(section(title: "Constraints", body: bulletize(constraints)))
        sections.append(section(title: "Deliverables", body: bulletize(deliverables)))
        sections.append(section(title: "Output Contract", body: bulletize(outputContractLines)))
        sections.append(section(title: "Pitfalls to Avoid", body: bulletize(profile.pitfallsAvoidLines)))
        sections.append(section(title: "Tactics", body: bulletize(profile.tacticsLines)))

        return sections.joined(separator: "\n\n")
    }

    private static func connectedModelLabel(for profile: PromptProfile) -> String {
        if profile.modelNames.isEmpty {
            return ConnectedModelSettings.unknownUnsetLabel
        }

        return profile.modelNames.joined(separator: ", ")
    }

    private static func section(title: String, body: String) -> String {
        "\(heading(title))\n\(body)"
    }

    private static func heading(_ title: String) -> String {
        "### \(title)"
    }

    private static func bulletize(_ lines: [String]) -> String {
        lines.map { "- \($0)" }.joined(separator: "\n")
    }
}
