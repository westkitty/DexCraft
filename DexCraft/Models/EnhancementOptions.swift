import Foundation

struct EnhancementOptions: Codable {
    var enforceMarkdown: Bool = true
    var noConversationalFiller: Bool = true
    var addFileTreeRequest: Bool = true
    var includeVerificationChecklist: Bool = true
    var includeRisksAndEdgeCases: Bool = true
    var includeAlternatives: Bool = true
    var includeValidationSteps: Bool = true
    var includeRevertPlan: Bool = true
    var preferSectionAwareParsing: Bool = true
    var includeSearchVerificationRequirements: Bool = false
    var strictCodeOnly: Bool = false

    enum CodingKeys: String, CodingKey {
        case enforceMarkdown
        case noConversationalFiller
        case addFileTreeRequest
        case includeVerificationChecklist
        case includeRisksAndEdgeCases
        case includeAlternatives
        case includeValidationSteps
        case includeRevertPlan
        case preferSectionAwareParsing
        case includeSearchVerificationRequirements
        case strictCodeOnly
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enforceMarkdown = try container.decodeIfPresent(Bool.self, forKey: .enforceMarkdown) ?? true
        noConversationalFiller = try container.decodeIfPresent(Bool.self, forKey: .noConversationalFiller) ?? true
        addFileTreeRequest = try container.decodeIfPresent(Bool.self, forKey: .addFileTreeRequest) ?? true
        includeVerificationChecklist = try container.decodeIfPresent(Bool.self, forKey: .includeVerificationChecklist) ?? true
        includeRisksAndEdgeCases = try container.decodeIfPresent(Bool.self, forKey: .includeRisksAndEdgeCases) ?? true
        includeAlternatives = try container.decodeIfPresent(Bool.self, forKey: .includeAlternatives) ?? true
        includeValidationSteps = try container.decodeIfPresent(Bool.self, forKey: .includeValidationSteps) ?? true
        includeRevertPlan = try container.decodeIfPresent(Bool.self, forKey: .includeRevertPlan) ?? true
        preferSectionAwareParsing = try container.decodeIfPresent(Bool.self, forKey: .preferSectionAwareParsing) ?? true
        includeSearchVerificationRequirements = try container.decodeIfPresent(Bool.self, forKey: .includeSearchVerificationRequirements) ?? false
        strictCodeOnly = try container.decodeIfPresent(Bool.self, forKey: .strictCodeOnly) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enforceMarkdown, forKey: .enforceMarkdown)
        try container.encode(noConversationalFiller, forKey: .noConversationalFiller)
        try container.encode(addFileTreeRequest, forKey: .addFileTreeRequest)
        try container.encode(includeVerificationChecklist, forKey: .includeVerificationChecklist)
        try container.encode(includeRisksAndEdgeCases, forKey: .includeRisksAndEdgeCases)
        try container.encode(includeAlternatives, forKey: .includeAlternatives)
        try container.encode(includeValidationSteps, forKey: .includeValidationSteps)
        try container.encode(includeRevertPlan, forKey: .includeRevertPlan)
        try container.encode(preferSectionAwareParsing, forKey: .preferSectionAwareParsing)
        try container.encode(includeSearchVerificationRequirements, forKey: .includeSearchVerificationRequirements)
        try container.encode(strictCodeOnly, forKey: .strictCodeOnly)
    }

    var activeConstraintCount: Int {
        [
            enforceMarkdown,
            noConversationalFiller,
            addFileTreeRequest,
            includeVerificationChecklist,
            includeRisksAndEdgeCases,
            includeAlternatives,
            includeValidationSteps,
            includeRevertPlan,
            preferSectionAwareParsing,
            includeSearchVerificationRequirements,
            strictCodeOnly
        ].filter { $0 }.count
    }
}
