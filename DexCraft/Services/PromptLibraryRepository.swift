import Foundation

protocol StorageBackend {
    func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T?
    func save<T: Encodable>(_ value: T, to filename: String) throws
    func delete(_ filename: String) throws
}

final class FileStorageBackend: StorageBackend {
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "DexCraft.FileStorageBackend.IO")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let appSupportURL: URL

    init(appFolderName: String = "DexCraft") {
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        appSupportURL = baseURL.appendingPathComponent(appFolderName, isDirectory: true)

        ioQueue.sync {
            do {
                try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            } catch {
                NSLog("DexCraft FileStorageBackend directory creation failed: \(error.localizedDescription)")
            }
        }
    }

    func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        try ioQueue.sync {
            let url = fileURL(for: filename)
            guard fileManager.fileExists(atPath: url.path) else {
                return nil
            }

            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        }
    }

    func save<T: Encodable>(_ value: T, to filename: String) throws {
        try ioQueue.sync {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: fileURL(for: filename), options: .atomic)
        }
    }

    func delete(_ filename: String) throws {
        try ioQueue.sync {
            let url = fileURL(for: filename)
            guard fileManager.fileExists(atPath: url.path) else {
                return
            }
            try fileManager.removeItem(at: url)
        }
    }

    private func fileURL(for filename: String) -> URL {
        appSupportURL.appendingPathComponent(filename, isDirectory: false)
    }
}

final class InMemoryStorageBackend: StorageBackend {
    private var dataStore: [String: Data] = [:]
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        lock.lock()
        defer { lock.unlock() }

        guard let data = dataStore[filename] else {
            return nil
        }

        return try decoder.decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, to filename: String) throws {
        lock.lock()
        defer { lock.unlock() }

        dataStore[filename] = try encoder.encode(value)
    }

    func delete(_ filename: String) throws {
        lock.lock()
        defer { lock.unlock() }
        dataStore.removeValue(forKey: filename)
    }
}

final class PromptLibraryRepository {
    static let defaultFilename = "prompt-library.json"
    static let versionHistoryCap = 50

    enum VersioningError: Error {
        case promptNotFound
        case versionNotFound
    }

    private let storageBackend: StorageBackend
    private let filename: String

    private(set) var bundle: PromptLibraryBundle = .empty

    var categories: [PromptCategory] { bundle.categories }
    var tags: [PromptTag] { bundle.tags }
    var prompts: [PromptLibraryItem] { bundle.prompts }

    init(storageBackend: StorageBackend = FileStorageBackend(), filename: String = PromptLibraryRepository.defaultFilename) {
        self.storageBackend = storageBackend
        self.filename = filename
        reload()
    }

    func reload() {
        let loaded = loadBundleBestEffort()
        bundle = loaded.bundle

        normalizeInPlace()
        if loaded.shouldPersist {
            persist()
        }
    }

    func persist() {
        normalizeInPlace()

        do {
            try storageBackend.save(bundle, to: filename)
        } catch {
            NSLog("DexCraft PromptLibraryRepository save failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createCategory(name: String) -> PromptCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let existing = bundle.categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }

        let category = PromptCategory(name: trimmed)
        bundle.categories.append(category)
        persist()
        return category
    }

    func deleteCategory(id: UUID) {
        let now = Date()
        bundle.categories.removeAll { $0.id == id }

        for index in bundle.prompts.indices where bundle.prompts[index].categoryId == id {
            bundle.prompts[index].categoryId = nil
            bundle.prompts[index].updatedAt = now
        }

        persist()
    }

    @discardableResult
    func createTag(name: String) -> PromptTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let existing = bundle.tags.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }

        let tag = PromptTag(name: trimmed)
        bundle.tags.append(tag)
        persist()
        return tag
    }

    func deleteTag(id: UUID) {
        let now = Date()
        bundle.tags.removeAll { $0.id == id }

        for index in bundle.prompts.indices {
            let originalCount = bundle.prompts[index].tagIds.count
            bundle.prompts[index].tagIds.removeAll { $0 == id }
            if bundle.prompts[index].tagIds.count != originalCount {
                bundle.prompts[index].updatedAt = now
            }
        }

        persist()
    }

    @discardableResult
    func createPrompt(
        title: String,
        body: String,
        categoryId: UUID? = nil,
        tagIds: [UUID] = []
    ) -> PromptLibraryItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let now = Date()
        let baselineVersion = PromptVersion(createdAt: now, note: nil, content: body)
        let prompt = PromptLibraryItem(
            title: trimmedTitle,
            body: body,
            categoryId: categoryId,
            tagIds: tagIds,
            versions: [baselineVersion],
            createdAt: now,
            updatedAt: now
        )
        bundle.prompts.append(prompt)
        persist()
        return prompt
    }

    func deletePrompt(id: UUID) {
        bundle.prompts.removeAll { $0.id == id }
        persist()
    }

    func updatePromptCategory(promptId: UUID, categoryId: UUID?) {
        guard let index = bundle.prompts.firstIndex(where: { $0.id == promptId }) else { return }
        bundle.prompts[index].categoryId = categoryId
        bundle.prompts[index].updatedAt = Date()
        persist()
    }

    func updatePromptTags(promptId: UUID, tagIds: [UUID]) {
        guard let index = bundle.prompts.firstIndex(where: { $0.id == promptId }) else { return }
        bundle.prompts[index].tagIds = tagIds
        bundle.prompts[index].updatedAt = Date()
        persist()
    }

    func updatePromptBody(promptId: UUID, body: String) {
        do {
            try addVersion(promptId: promptId, content: body, note: nil)
        } catch {
            NSLog("DexCraft PromptLibraryRepository update body failed: \(error.localizedDescription)")
        }
    }

    func versions(for promptId: UUID) -> [PromptVersion] {
        bundle.prompts.first(where: { $0.id == promptId })?.versions ?? []
    }

    func addVersion(promptId: UUID, content: String, note: String?) throws {
        guard let index = bundle.prompts.firstIndex(where: { $0.id == promptId }) else {
            throw VersioningError.promptNotFound
        }

        let isRollback = note?.lowercased().contains("rollback") == true
        let currentContent = bundle.prompts[index].body
        guard isRollback || currentContent != content else {
            return
        }

        let now = Date()
        let normalizedNote = normalizedVersionNote(note)
        let version = PromptVersion(createdAt: now, note: normalizedNote, content: content)

        bundle.prompts[index].body = content
        bundle.prompts[index].updatedAt = now
        bundle.prompts[index].versions.insert(version, at: 0)
        persist()
    }

    func rollback(promptId: UUID, to versionId: UUID) throws {
        guard let prompt = bundle.prompts.first(where: { $0.id == promptId }) else {
            throw VersioningError.promptNotFound
        }

        guard let version = prompt.versions.first(where: { $0.id == versionId }) else {
            throw VersioningError.versionNotFound
        }

        try addVersion(
            promptId: promptId,
            content: version.content,
            note: "Rollback to version \(version.id.uuidString)"
        )
    }

    func searchPrompts(query: String, categoryId: UUID? = nil, tagId: UUID? = nil) -> [PromptLibraryItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagsById = Dictionary(uniqueKeysWithValues: bundle.tags.map { ($0.id, $0.name.lowercased()) })

        return bundle.prompts.filter { prompt in
            if let categoryId, prompt.categoryId != categoryId {
                return false
            }

            if let tagId, !prompt.tagIds.contains(tagId) {
                return false
            }

            guard !normalizedQuery.isEmpty else {
                return true
            }

            if matchesSearch(prompt.title, query: normalizedQuery) {
                return true
            }

            if matchesSearch(prompt.body, query: normalizedQuery) {
                return true
            }

            let promptTagNames = prompt.tagIds.compactMap { tagsById[$0] }
            return promptTagNames.contains { matchesSearch($0, query: normalizedQuery) }
        }
    }

    func categoryName(for id: UUID?) -> String {
        guard let id else { return "Uncategorized" }
        return bundle.categories.first(where: { $0.id == id })?.name ?? "Uncategorized"
    }

    func tagNames(for tagIds: [UUID]) -> [String] {
        let tagsById = Dictionary(uniqueKeysWithValues: bundle.tags.map { ($0.id, $0.name) })
        return tagIds.compactMap { tagsById[$0] }
    }

    private func normalizeInPlace() {
        let normalizedCategories = bundle.categories.sorted { lhs, rhs in
            let lhsName = lhs.name.lowercased()
            let rhsName = rhs.name.lowercased()
            if lhsName == rhsName {
                return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
            }
            return lhsName < rhsName
        }

        let normalizedTags = bundle.tags.sorted { lhs, rhs in
            let lhsName = lhs.name.lowercased()
            let rhsName = rhs.name.lowercased()
            if lhsName == rhsName {
                return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
            }
            return lhsName < rhsName
        }

        let categoryIDs = Set(normalizedCategories.map(\.id))
        let tagNameByID = Dictionary(uniqueKeysWithValues: normalizedTags.map { ($0.id, $0.name.lowercased()) })

        let normalizedPrompts = bundle.prompts.map { prompt -> PromptLibraryItem in
            var normalizedPrompt = prompt
            if let categoryId = prompt.categoryId, !categoryIDs.contains(categoryId) {
                normalizedPrompt.categoryId = nil
            }

            if normalizedPrompt.versions.isEmpty {
                normalizedPrompt.versions = [
                    PromptVersion(createdAt: normalizedPrompt.createdAt, note: nil, content: normalizedPrompt.body)
                ]
            } else {
                normalizedPrompt.versions = normalizedPrompt.versions
                    .enumerated()
                    .sorted { lhs, rhs in
                        let lhsVersion = lhs.element
                        let rhsVersion = rhs.element
                        if lhsVersion.createdAt == rhsVersion.createdAt {
                            // Preserve existing order for equal timestamps to keep newest-first
                            // insertion behavior stable across save/load cycles.
                            return lhs.offset < rhs.offset
                        }
                        return lhsVersion.createdAt > rhsVersion.createdAt
                    }
                    .map(\.element)
                if normalizedPrompt.versions.count > Self.versionHistoryCap {
                    normalizedPrompt.versions = Array(normalizedPrompt.versions.prefix(Self.versionHistoryCap))
                }
            }
            normalizedPrompt.tagIds = normalizedTagIDs(from: prompt.tagIds, tagNameByID: tagNameByID)
            return normalizedPrompt
        }.sorted { lhs, rhs in
            let lhsTitle = lhs.title.lowercased()
            let rhsTitle = rhs.title.lowercased()
            if lhsTitle == rhsTitle {
                return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
            }
            return lhsTitle < rhsTitle
        }

        bundle = PromptLibraryBundle(
            categories: normalizedCategories,
            tags: normalizedTags,
            prompts: normalizedPrompts
        )
    }

    private func loadBundleBestEffort() -> (bundle: PromptLibraryBundle, shouldPersist: Bool) {
        var encounteredDecodeFailure = false

        let currentBundleLoad = tryLoad(PromptLibraryBundle.self)
        if let currentBundle = currentBundleLoad.value {
            return (currentBundle, true)
        }
        encounteredDecodeFailure = encounteredDecodeFailure || currentBundleLoad.hadError

        // Legacy shape: top-level prompt array only.
        let promptsOnlyLoad = tryLoad([PromptLibraryItem].self)
        if let promptsOnly = promptsOnlyLoad.value {
            return (PromptLibraryBundle(categories: [], tags: [], prompts: promptsOnly), true)
        }
        encounteredDecodeFailure = encounteredDecodeFailure || promptsOnlyLoad.hadError

        // Legacy shape: object with optional arrays and prompts without versions.
        let legacyBundleLoad = tryLoad(LegacyPromptLibraryBundle.self)
        if let legacyBundle = legacyBundleLoad.value {
            return (PromptLibraryBundle(
                categories: legacyBundle.categories ?? [],
                tags: legacyBundle.tags ?? [],
                prompts: (legacyBundle.prompts ?? []).map { $0.toPromptLibraryItem() }
            ), true)
        }
        encounteredDecodeFailure = encounteredDecodeFailure || legacyBundleLoad.hadError

        // Avoid destructive overwrite when decoding fails for existing unknown/corrupt data.
        if encounteredDecodeFailure {
            return (.empty, false)
        }

        // Missing file / first launch: persist normalized empty bundle.
        return (.empty, true)
    }

    private func tryLoad<T: Decodable>(_ type: T.Type) -> (value: T?, hadError: Bool) {
        do {
            return (try storageBackend.load(type, from: filename), false)
        } catch {
            NSLog("DexCraft PromptLibraryRepository decode as \(String(describing: type)) failed: \(error.localizedDescription)")
            return (nil, true)
        }
    }

    private func normalizedTagIDs(from tagIds: [UUID], tagNameByID: [UUID: String]) -> [UUID] {
        var seen = Set<UUID>()
        let deduped = tagIds.filter { seen.insert($0).inserted }

        return deduped.sorted { lhs, rhs in
            let lhsSort = tagNameByID[lhs] ?? lhs.uuidString.lowercased()
            let rhsSort = tagNameByID[rhs] ?? rhs.uuidString.lowercased()

            if lhsSort == rhsSort {
                return lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
            }
            return lhsSort < rhsSort
        }
    }

    private func matchesSearch(_ text: String, query: String) -> Bool {
        let normalizedText = text.lowercased()

        // Keep short queries precise so "ui" does not match unrelated words like "Builder".
        if query.count <= 2 {
            let tokens = normalizedText.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return tokens.contains { $0 == query }
        }

        return normalizedText.contains(query)
    }

    private func normalizedVersionNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

private struct LegacyPromptLibraryBundle: Decodable {
    let categories: [PromptCategory]?
    let tags: [PromptTag]?
    let prompts: [LegacyPromptLibraryItem]?
}

private struct LegacyPromptLibraryItem: Decodable {
    let id: UUID?
    let title: String?
    let body: String?
    let categoryId: UUID?
    let tagIds: [UUID]?
    let createdAt: Date?
    let updatedAt: Date?

    func toPromptLibraryItem() -> PromptLibraryItem {
        let resolvedId = id ?? UUID()
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (title ?? "Untitled Prompt")
            : "Untitled Prompt"
        let resolvedBody = body ?? ""
        let resolvedCreatedAt = createdAt ?? Date()
        let resolvedUpdatedAt = updatedAt ?? resolvedCreatedAt

        return PromptLibraryItem(
            id: resolvedId,
            title: resolvedTitle,
            body: resolvedBody,
            categoryId: categoryId,
            tagIds: tagIds ?? [],
            versions: [],
            createdAt: resolvedCreatedAt,
            updatedAt: resolvedUpdatedAt
        )
    }
}

private struct PromptAnalyticsBundle: Codable, Equatable {
    var runs: [PromptRunRecord]

    static let empty = PromptAnalyticsBundle(runs: [])
}

final class AnalyticsRepository {
    static let defaultFilename = "prompt-analytics.json"

    private let storageBackend: StorageBackend
    private let filename: String
    private let dayFormatter: DateFormatter

    private var bundle: PromptAnalyticsBundle = .empty

    init(storageBackend: StorageBackend = FileStorageBackend(), filename: String = AnalyticsRepository.defaultFilename) {
        self.storageBackend = storageBackend
        self.filename = filename

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        dayFormatter = formatter

        reload()
    }

    func reload() {
        let loaded = loadBundleBestEffort()
        bundle = loaded.bundle
        normalizeInPlace()
        if loaded.shouldPersist {
            persist()
        }
    }

    func persist() {
        normalizeInPlace()

        do {
            try storageBackend.save(bundle, to: filename)
        } catch {
            NSLog("DexCraft AnalyticsRepository save failed: \(error.localizedDescription)")
        }
    }

    func addRun(record: PromptRunRecord) {
        bundle.runs.append(record)
        persist()
    }

    @discardableResult
    func addRun(
        promptId: UUID,
        input: String,
        output: String,
        adapterId: String,
        durationMs: Int,
        timestamp: Date = Date()
    ) -> PromptRunRecord {
        let record = PromptRunRecord(
            promptId: promptId,
            timestamp: timestamp,
            inputLengthChars: input.count,
            outputLengthChars: output.count,
            estimatedTokensInput: TokenEstimator.estimate(for: input),
            estimatedTokensOutput: TokenEstimator.estimate(for: output),
            adapterId: adapterId,
            durationMs: durationMs
        )
        addRun(record: record)
        return record
    }

    func listRuns(promptId: UUID) -> [PromptRunRecord] {
        bundle.runs.filter { $0.promptId == promptId }
    }

    func runCount(promptId: UUID) -> Int {
        listRuns(promptId: promptId).count
    }

    // Policy: average output tokens, rounded down.
    func averageTokens(promptId: UUID) -> Int {
        let runs = listRuns(promptId: promptId)
        guard !runs.isEmpty else { return 0 }
        let total = runs.reduce(0) { $0 + $1.estimatedTokensOutput }
        return Int(Double(total) / Double(runs.count))
    }

    func dailyCounts(promptId: UUID) -> [String: Int] {
        var counts: [String: Int] = [:]

        for run in listRuns(promptId: promptId) {
            let key = dayFormatter.string(from: run.timestamp)
            counts[key, default: 0] += 1
        }

        return counts
    }

    private func normalizeInPlace() {
        bundle.runs = bundle.runs.sorted { lhs, rhs in
            if lhs.promptId != rhs.promptId {
                return lhs.promptId.uuidString.lowercased() < rhs.promptId.uuidString.lowercased()
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
        }
    }

    private func loadBundleBestEffort() -> (bundle: PromptAnalyticsBundle, shouldPersist: Bool) {
        var encounteredDecodeFailure = false

        let currentBundleLoad = tryLoad(PromptAnalyticsBundle.self)
        if let currentBundle = currentBundleLoad.value {
            return (currentBundle, true)
        }
        encounteredDecodeFailure = encounteredDecodeFailure || currentBundleLoad.hadError

        let legacyRunsLoad = tryLoad([PromptRunRecord].self)
        if let legacyRuns = legacyRunsLoad.value {
            return (PromptAnalyticsBundle(runs: legacyRuns), true)
        }
        encounteredDecodeFailure = encounteredDecodeFailure || legacyRunsLoad.hadError

        if encounteredDecodeFailure {
            return (.empty, false)
        }

        return (.empty, true)
    }

    private func tryLoad<T: Decodable>(_ type: T.Type) -> (value: T?, hadError: Bool) {
        do {
            return (try storageBackend.load(type, from: filename), false)
        } catch {
            NSLog("DexCraft AnalyticsRepository decode as \(String(describing: type)) failed: \(error.localizedDescription)")
            return (nil, true)
        }
    }
}
