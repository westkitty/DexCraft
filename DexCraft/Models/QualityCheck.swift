import Foundation

struct QualityCheck: Identifiable {
    let id: String
    let title: String
    let passed: Bool

    init(id: String? = nil, title: String, passed: Bool) {
        self.id = id ?? title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        self.title = title
        self.passed = passed
    }
}
