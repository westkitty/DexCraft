import Foundation

enum WorkbenchTab: String, CaseIterable, Identifiable {
    case enhance = "Enhance"
    case templates = "Templates"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }
}
