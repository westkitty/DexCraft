import Foundation

struct QualityCheck: Identifiable {
    let id = UUID()
    let title: String
    let passed: Bool
}
