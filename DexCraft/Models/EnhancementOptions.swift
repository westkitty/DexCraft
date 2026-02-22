import Foundation

struct EnhancementOptions: Codable {
    var enforceMarkdown: Bool = true
    var noConversationalFiller: Bool = true
    var addFileTreeRequest: Bool = true
    var includeVerificationChecklist: Bool = true
    var strictCodeOnly: Bool = false

    var activeConstraintCount: Int {
        [
            enforceMarkdown,
            noConversationalFiller,
            addFileTreeRequest,
            includeVerificationChecklist,
            strictCodeOnly
        ].filter { $0 }.count
    }
}
