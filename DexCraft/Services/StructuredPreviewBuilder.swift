import Foundation

struct Draft: Equatable {
    var goal: String
    var context: String
    var constraints: [String]
    var deliverables: [String]
}

enum Format: String, CaseIterable, Identifiable {
    case plainText = "PlainText"
    case json = "JSON"
    case markdown = "Markdown"

    var id: String { rawValue }
}

func buildPreview(draft: Draft, format: Format) -> String {
    switch format {
    case .plainText:
        return buildPlainTextPreview(draft: draft)
    case .json:
        return buildJSONPreview(draft: draft)
    case .markdown:
        return buildMarkdownPreview(draft: draft)
    }
}

private func buildPlainTextPreview(draft: Draft) -> String {
    var sections: [String] = []

    let goal = draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    if !goal.isEmpty {
        sections.append("Goal:\n\(goal)")
    }

    let context = draft.context.trimmingCharacters(in: .whitespacesAndNewlines)
    if !context.isEmpty {
        sections.append("Context:\n\(context)")
    }

    if !draft.constraints.isEmpty {
        let lines = draft.constraints.map { "- \($0)" }.joined(separator: "\n")
        sections.append("Constraints:\n\(lines)")
    }

    if !draft.deliverables.isEmpty {
        let lines = draft.deliverables.map { "- \($0)" }.joined(separator: "\n")
        sections.append("Deliverables:\n\(lines)")
    }

    return sections.joined(separator: "\n\n")
}

private func buildMarkdownPreview(draft: Draft) -> String {
    var sections: [String] = []

    let goal = draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    if !goal.isEmpty {
        sections.append("## Goal\n\(goal)")
    }

    let context = draft.context.trimmingCharacters(in: .whitespacesAndNewlines)
    if !context.isEmpty {
        sections.append("## Context\n\(context)")
    }

    if !draft.constraints.isEmpty {
        let lines = draft.constraints.map { "- \($0)" }.joined(separator: "\n")
        sections.append("## Constraints\n\(lines)")
    }

    if !draft.deliverables.isEmpty {
        let lines = draft.deliverables.map { "- \($0)" }.joined(separator: "\n")
        sections.append("## Deliverables\n\(lines)")
    }

    return sections.joined(separator: "\n\n")
}

private func buildJSONPreview(draft: Draft) -> String {
    let normalized = Draft(
        goal: draft.goal.trimmingCharacters(in: .whitespacesAndNewlines),
        context: draft.context.trimmingCharacters(in: .whitespacesAndNewlines),
        constraints: draft.constraints,
        deliverables: draft.deliverables
    )

    struct PreviewPayload: Codable {
        let goal: String
        let context: String
        let constraints: [String]
        let deliverables: [String]
    }

    let payload = PreviewPayload(
        goal: normalized.goal,
        context: normalized.context,
        constraints: normalized.constraints,
        deliverables: normalized.deliverables
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        return "{}"
    }
}
