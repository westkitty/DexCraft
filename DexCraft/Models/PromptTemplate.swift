import Foundation

struct PromptTemplate: Codable, Identifiable {
    static var migrationNow: () -> Date = { Date() }
    static let uncategorizedCategory = "Uncategorized"

    let id: UUID
    var name: String
    var content: String
    var target: PromptTarget
    var createdAt: Date
    var category: String
    var tags: [String]
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case content
        case target
        case createdAt
        case category
        case tags
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        target: PromptTarget,
        createdAt: Date = Date(),
        category: String = PromptTemplate.uncategorizedCategory,
        tags: [String] = [],
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.target = target
        self.createdAt = createdAt
        self.category = PromptTemplate.normalizedCategory(category)
        self.tags = PromptTemplate.normalizedTags(tags)
        self.updatedAt = updatedAt ?? createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name)) ?? "Untitled Template"
        content = (try? container.decode(String.self, forKey: .content)) ?? ""
        target = (try? container.decode(PromptTarget.self, forKey: .target)) ?? .claude

        let migratedCreatedAt = PromptTemplate.decodeDate(from: container, forKey: .createdAt) ?? PromptTemplate.migrationNow()
        createdAt = migratedCreatedAt
        updatedAt = PromptTemplate.decodeDate(from: container, forKey: .updatedAt) ?? migratedCreatedAt

        let rawCategory = (try? container.decode(String.self, forKey: .category)) ?? PromptTemplate.uncategorizedCategory
        category = PromptTemplate.normalizedCategory(rawCategory)
        tags = PromptTemplate.normalizedTags((try? container.decode([String].self, forKey: .tags)) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
        try container.encode(target, forKey: .target)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
        if let value = try? container.decode(Date.self, forKey: key) {
            return value
        }
        if let rawString = try? container.decode(String.self, forKey: key) {
            return parseISO8601Date(rawString)
        }
        return nil
    }

    private static func parseISO8601Date(_ rawValue: String) -> Date? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: trimmed)
    }

    private static func normalizedCategory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? uncategorizedCategory : trimmed
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for tag in values {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lowered = trimmed.lowercased()
            if seen.insert(lowered).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
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

enum TemplateSortOption: String, CaseIterable, Codable, Identifiable {
    case recentlyUpdated = "Recently Updated"
    case recentlyCreated = "Recently Created"
    case nameAscending = "Name (A-Z)"

    var id: String { rawValue }
}

func computeVisibleTemplates(
    templates: [PromptTemplate],
    query: String,
    categoryFilter: String?,
    targetFilter: PromptTarget?,
    sort: TemplateSortOption,
    locale: Locale
) -> [PromptTemplate] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedCategoryFilter = categoryFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    let filtered = templates.filter { template in
        if let normalizedCategoryFilter {
            let templateCategory = template.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard templateCategory == normalizedCategoryFilter else { return false }
        }

        if let targetFilter {
            guard template.target == targetFilter else { return false }
        }

        guard !normalizedQuery.isEmpty else { return true }

        if template.name.lowercased().contains(normalizedQuery) {
            return true
        }

        if template.category.lowercased().contains(normalizedQuery) {
            return true
        }

        return template.tags.contains(where: { $0.lowercased().contains(normalizedQuery) })
    }

    let sorted = filtered.sorted { lhs, rhs in
        switch sort {
        case .recentlyUpdated:
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            let nameCompare = localizedCaseInsensitiveNameCompare(lhs.name, rhs.name, locale: locale)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString

        case .recentlyCreated:
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            let nameCompare = localizedCaseInsensitiveNameCompare(lhs.name, rhs.name, locale: locale)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString

        case .nameAscending:
            let nameCompare = localizedCaseInsensitiveNameCompare(lhs.name, rhs.name, locale: locale)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    return sorted
}

enum TemplateCategoryOperations {
    static func renameCategory(templates: [PromptTemplate], from source: String, to destination: String) -> [PromptTemplate] {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty, !normalizedDestination.isEmpty else {
            return templates
        }

        return templates.map { template in
            guard template.category.caseInsensitiveCompare(normalizedSource) == .orderedSame else {
                return template
            }
            var updated = template
            updated.category = normalizedDestination
            return updated
        }
    }

    static func mergeCategory(templates: [PromptTemplate], source: String, destination: String) -> [PromptTemplate] {
        renameCategory(templates: templates, from: source, to: destination)
    }

    static func deleteCategory(templates: [PromptTemplate], category: String) -> [PromptTemplate] {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCategory.isEmpty else {
            return templates
        }

        return templates.map { template in
            guard template.category.caseInsensitiveCompare(normalizedCategory) == .orderedSame else {
                return template
            }
            var updated = template
            updated.category = PromptTemplate.uncategorizedCategory
            return updated
        }
    }
}

private func localizedCaseInsensitiveNameCompare(_ lhs: String, _ rhs: String, locale: Locale) -> ComparisonResult {
    lhs.compare(
        rhs,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: nil,
        locale: locale
    )
}
