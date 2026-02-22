import Foundation

struct PromptTemplate: Codable, Identifiable {
    let id: UUID
    var name: String
    var content: String
    var target: PromptTarget
    var createdAt: Date

    init(id: UUID = UUID(), name: String, content: String, target: PromptTarget, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.target = target
        self.createdAt = createdAt
    }

    static func defaultPresets() -> [PromptTemplate] {
        [
            PromptTemplate(
                name: "Repo Audit + Refactor Plan",
                content: """
                ### Goal
                Audit the repository and deliver a deterministic refactor plan.

                ### Context
                Review existing architecture, hotspots, and technical debt.

                ### Constraints
                - Preserve public behavior unless an explicit regression fix is requested.
                - Use reproducible commands and avoid destructive git operations.

                ### Deliverables
                - Concrete file tree request before implementation details.
                - Prioritized implementation plan and validation checklist.
                """,
                target: .agenticIDE
            ),
            PromptTemplate(
                name: "Bug Reproduction + Minimal Fix",
                content: """
                ### Goal
                Reproduce the reported bug and implement the smallest safe fix.

                ### Context
                Capture current behavior, expected behavior, and environment assumptions.

                ### Constraints
                - Prefer minimal blast radius changes.
                - Add regression validation for the specific failure mode.

                ### Deliverables
                - Reproduction notes.
                - Patch plan and targeted code changes.
                - Verification checklist with pass/fail status.
                """,
                target: .geminiChatGPT
            ),
            PromptTemplate(
                name: "Docs Rewrite (Strict Headings)",
                content: """
                ### Goal
                Rewrite documentation for clarity and operational usefulness.

                ### Context
                Existing docs are inconsistent and omit validation details.

                ### Constraints
                - Use strict heading structure and concise language.
                - Preserve technical accuracy and call out assumptions.

                ### Deliverables
                - Final documentation in strict markdown.
                - Validation checklist and rollback notes.
                """,
                target: .claude
            ),
            PromptTemplate(
                name: "Agentic Feature + Tests + Rollback",
                content: """
                ### Goal
                Implement the requested feature with deterministic file edits and tests.

                ### Context
                Work within the existing codebase patterns and avoid speculative rewrites.

                ### Constraints
                - Show exact file tree before implementation details.
                - Include build/test commands and rollback plan.

                ### Deliverables
                - Ordered file modifications.
                - Validation steps with expected outcomes.
                - Revert plan tied to changed files.
                """,
                target: .agenticIDE
            )
        ]
    }
}
