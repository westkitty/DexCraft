import Foundation

final class QualityCheckEngine {
    func evaluate(
        ctx: PromptBuildContext,
        sections: PromptSectionsConfig,
        variableResult: VariableResolutionResult,
        generatedPrompt: String
    ) -> [QualityCheck] {
        let trimmedGoal = ctx.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let goalPassed = !sections.includeGoal || !trimmedGoal.isEmpty
        let goalDefined = trimmedGoal.count >= 12

        let missingVariables = variableResult.unfilled
        let variablesPassed = missingVariables.isEmpty

        let nonEmptyConstraints = ctx.constraints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let constraintsPassed = !sections.includeConstraints || !nonEmptyConstraints.isEmpty
        let constraintsActive = !sections.includeConstraints || !nonEmptyConstraints.isEmpty

        let outputSizePassed = generatedPrompt.count >= 200 && generatedPrompt.count <= 20_000

        return [
            QualityCheck(
                title: "Goal presence",
                passed: goalPassed,
                severity: .error,
                detail: goalPassed ? nil : "Goal section is enabled, but the goal is empty."
            ),
            QualityCheck(
                title: "Goal Defined",
                passed: goalDefined,
                severity: .warning,
                detail: goalDefined ? nil : "Goal must be at least 12 non-whitespace characters."
            ),
            QualityCheck(
                title: "Variable completeness",
                passed: variablesPassed,
                severity: .error,
                detail: variablesPassed ? nil : "Missing values for: \(missingVariables.joined(separator: ", "))"
            ),
            QualityCheck(
                title: "Constraints coverage",
                passed: constraintsPassed,
                severity: .warning,
                detail: constraintsPassed ? nil : "Constraints section is enabled, but no constraints were provided."
            ),
            QualityCheck(
                title: "Constraints Active",
                passed: constraintsActive,
                severity: .warning,
                detail: constraintsActive ? nil : "Enable or supply at least one non-empty constraint."
            ),
            QualityCheck(
                title: "Output size sanity",
                passed: outputSizePassed,
                severity: .warning,
                detail: outputSizePassed ? nil : outputSizeDetail(for: generatedPrompt.count)
            )
        ]
    }

    private func outputSizeDetail(for length: Int) -> String {
        if length < 200 {
            return "Generated prompt is too short (\(length) characters; minimum is 200)."
        }

        return "Generated prompt is too long (\(length) characters; maximum is 20000)."
    }
}
