import Foundation

final class StorageManager {
    private enum StorageFile: String {
        case templates = "templates.json"
        case history = "history.json"
        case connectedModelSettings = "connected-model-settings.json"
        case optimizerWeights = "optimizer-weights.json"
    }

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "DexCraft.StorageManager.IO")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let appSupportURL: URL

    init(appFolderName: String = "DexCraft") {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        self.appSupportURL = baseURL.appendingPathComponent(appFolderName, isDirectory: true)

        ensureAppSupportDirectory()
    }

    func loadTemplates() -> [PromptTemplate] {
        load([PromptTemplate].self, from: .templates) ?? []
    }

    func saveTemplates(_ templates: [PromptTemplate]) {
        save(templates, to: .templates)
    }

    func loadHistory() -> [PromptHistoryEntry] {
        load([PromptHistoryEntry].self, from: .history) ?? []
    }

    func saveHistory(_ history: [PromptHistoryEntry]) {
        let capped = Array(history.prefix(50))
        save(capped, to: .history)
    }

    func loadConnectedModelSettings() -> ConnectedModelSettings {
        load(ConnectedModelSettings.self, from: .connectedModelSettings) ?? ConnectedModelSettings()
    }

    func saveConnectedModelSettings(_ settings: ConnectedModelSettings) {
        save(settings, to: .connectedModelSettings)
    }

    func loadOptimizerWeights() -> HeuristicScoringWeights? {
        load(HeuristicScoringWeights.self, from: .optimizerWeights)
    }

    func saveOptimizerWeights(_ weights: HeuristicScoringWeights) {
        save(weights.clamped(), to: .optimizerWeights)
    }

    private func ensureAppSupportDirectory() {
        ioQueue.sync {
            if !fileManager.fileExists(atPath: appSupportURL.path) {
                do {
                    try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                } catch {
                    NSLog("DexCraft StorageManager directory creation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func fileURL(for file: StorageFile) -> URL {
        appSupportURL.appendingPathComponent(file.rawValue, isDirectory: false)
    }

    private func load<T: Decodable>(_ type: T.Type, from file: StorageFile) -> T? {
        ioQueue.sync {
            let url = fileURL(for: file)
            guard fileManager.fileExists(atPath: url.path) else {
                return nil
            }

            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(type, from: data)
            } catch {
                NSLog("DexCraft StorageManager load failed for \(file.rawValue): \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func save<T: Encodable>(_ object: T, to file: StorageFile) {
        ioQueue.async { [fileManager, encoder, appSupportURL] in
            let url = appSupportURL.appendingPathComponent(file.rawValue, isDirectory: false)

            do {
                if !fileManager.fileExists(atPath: appSupportURL.path) {
                    try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                }

                let data = try encoder.encode(object)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("DexCraft StorageManager save failed for \(file.rawValue): \(error.localizedDescription)")
            }
        }
    }
}
