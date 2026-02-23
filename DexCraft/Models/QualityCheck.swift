import Foundation

enum QualitySeverity: String, Codable, Equatable {
    case info
    case warning
    case error
}

struct QualityCheck: Equatable, Identifiable {
    let title: String
    let passed: Bool
    let severity: QualitySeverity
    let detail: String?

    var id: String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
    }

    init(
        title: String,
        passed: Bool,
        severity: QualitySeverity = .info,
        detail: String? = nil
    ) {
        self.title = title
        self.passed = passed
        self.severity = severity
        self.detail = detail
    }
}
