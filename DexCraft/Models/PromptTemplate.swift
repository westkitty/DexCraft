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
                name: "GitHub Repo Bootstrap + First Push",
                content: """
                ### Goal
                Initialize a local project as a Git repository and publish it to GitHub with a clean first commit.

                ### Context
                A local codebase is ready, and the target remote repository should be configured and pushed safely.

                ### Constraints
                - Use reproducible commands and avoid destructive git operations.
                - Include branch naming and commit message conventions.
                - Validate remote configuration before pushing.

                ### Deliverables
                - Ordered shell commands to initialize, add remote, commit, and push.
                - A rollback path for incorrect remote or accidental commit content.
                - Verification checklist confirming GitHub sync success.
                """,
                target: .agenticIDE
            ),
            PromptTemplate(
                name: "Issue to PR Delivery Plan",
                content: """
                ### Goal
                Convert a GitHub issue into a deterministic implementation plan and pull request checklist.

                ### Context
                The issue is already described and needs an execution plan that leads to a reviewable PR.

                ### Constraints
                - Keep scope tightly aligned to acceptance criteria.
                - Include branch strategy and commit slicing.
                - Include test and review gates before merge.

                ### Deliverables
                - Implementation steps mapped to files.
                - PR body template with risk, testing, and rollback sections.
                - Final pass/fail readiness checklist.
                """,
                target: .agenticIDE
            ),
            PromptTemplate(
                name: "GitHub Actions CI Pipeline Setup",
                content: """
                ### Goal
                Create a robust CI workflow using GitHub Actions for build, lint, and test validation.

                ### Context
                The repository needs automated checks on pull requests and protected branches.

                ### Constraints
                - Use deterministic workflow triggers.
                - Keep jobs parallelized where safe and cached where useful.
                - Report failures with actionable diagnostics.

                ### Deliverables
                - `.github/workflows` file plan with exact filenames.
                - Build/run matrix and required status check recommendations.
                - Validation and rollback checklist for workflow rollout.
                """,
                target: .agenticIDE
            ),
            PromptTemplate(
                name: "Release Notes + Changelog Draft",
                content: """
                ### Goal
                Generate release notes and changelog content from merged work with clear impact summaries.

                ### Context
                A release branch is ready and needs structured notes for developers and stakeholders.

                ### Constraints
                - Group changes by feature, fix, and maintenance.
                - Call out breaking changes and migration instructions explicitly.
                - Keep wording concise and factual.

                ### Deliverables
                - Draft `CHANGELOG.md` update section.
                - Draft GitHub Release body.
                - Verification checklist for completeness and accuracy.
                """,
                target: .geminiChatGPT
            ),
            PromptTemplate(
                name: "Issue + PR Template Authoring",
                content: """
                ### Goal
                Create high-signal GitHub issue and pull request templates that improve triage and review quality.

                ### Context
                The repository lacks standardized reporting and PR context, causing inconsistent submissions.

                ### Constraints
                - Keep templates concise but complete.
                - Require reproduction and validation details for bugs.
                - Require risk and test evidence for pull requests.

                ### Deliverables
                - Proposed files under `.github/ISSUE_TEMPLATE` and `.github/pull_request_template.md`.
                - Final template content with mandatory checklist items.
                - Verification checklist for usability and maintainability.
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
                name: "Security Dependency Update Sweep",
                content: """
                ### Goal
                Analyze dependency vulnerabilities and propose a safe upgrade plan with rollback strategy.

                ### Context
                Security alerts and outdated packages require controlled remediation without destabilizing production.

                ### Constraints
                - Prioritize critical and high vulnerabilities first.
                - Avoid major-version upgrades without explicit impact analysis.
                - Include post-upgrade verification and rollback steps.

                ### Deliverables
                - Dependency risk matrix and upgrade order.
                - Concrete file/package changes and commands.
                - Validation checklist including security scan reruns.
                """,
                target: .perplexity
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
                name: "Feature Refactor + Regression Tests",
                content: """
                ### Goal
                Refactor a feature for maintainability while preserving behavior through targeted regression tests.

                ### Context
                Existing code is difficult to extend and has inconsistent test coverage.

                ### Constraints
                - Preserve public behavior unless explicitly changed.
                - Keep refactor incremental and reviewable.
                - Add tests for high-risk behavior boundaries.

                ### Deliverables
                - Refactor plan by file and module.
                - New/updated tests with expected outcomes.
                - Verification checklist and rollback plan.
                """,
                target: .agenticIDE
            ),
            PromptTemplate(
                name: "Production Incident Triage + Recovery",
                content: """
                ### Goal
                Triage a production incident, identify probable root causes, and provide a controlled recovery plan.

                ### Context
                A live issue is impacting users and requires rapid but safe diagnosis and mitigation.

                ### Constraints
                - Separate confirmed facts from hypotheses.
                - Prioritize mitigations that reduce user impact quickly.
                - Include communication and rollback guardrails.

                ### Deliverables
                - Incident timeline and triage plan.
                - Recovery actions with validation checkpoints.
                - Post-incident follow-up checklist for prevention.
                """,
                target: .perplexity
            )
        ]
    }
}
