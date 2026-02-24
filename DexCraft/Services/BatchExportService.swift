import Foundation

final class BatchExportService {
    private struct BatchOutput: Encodable {
        let id: String
        let input: String
        let currentOutput: String

        enum CodingKeys: String, CodingKey {
            case id
            case input
            case currentOutput = "current_output"
        }
    }

    struct BatchRunSummary {
        let processedCount: Int
        let failureCount: Int
    }

    enum BatchExportError: LocalizedError {
        case invalidTopLevelJSON

        var errorDescription: String? {
            switch self {
            case .invalidTopLevelJSON:
                return "Input JSON must be a top-level array."
            }
        }
    }

    static func appSupportDirURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: ("~/Library/Application Support" as NSString).expandingTildeInPath, isDirectory: true)
        return base.appendingPathComponent("DexCraft", isDirectory: true)
    }

    static func ensureDirExists(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func inputsURL() -> URL {
        appSupportDirURL().appendingPathComponent("dexcraft_batch_inputs.json", isDirectory: false)
    }

    static func outputsURL() -> URL {
        appSupportDirURL().appendingPathComponent("dexcraft_batch_outputs.json", isDirectory: false)
    }

    static func writeBatchInputsTemplate(to url: URL) throws {
        try ensureDirExists(url.deletingLastPathComponent())
        guard let data = batchInputsTemplate.data(using: .utf8) else { return }
        try data.write(to: url, options: .atomic)
    }

    static func run(inputURL: URL, outputURL: URL) throws {
        _ = try runBatchExport(inputsURL: inputURL, outputsURL: outputURL)
    }

    static func runBatchExport(inputsURL: URL, outputsURL: URL) throws -> BatchRunSummary {
        if Thread.isMainThread {
            return try runBatchExportOnMain(inputsURL: inputsURL, outputsURL: outputsURL)
        }

        var summary: BatchRunSummary?
        var capturedError: Error?
        DispatchQueue.main.sync {
            do {
                summary = try runBatchExportOnMain(inputsURL: inputsURL, outputsURL: outputsURL)
            } catch {
                capturedError = error
            }
        }

        if let capturedError {
            throw capturedError
        }

        return summary ?? BatchRunSummary(processedCount: 0, failureCount: 0)
    }

    private static func runBatchExportOnMain(inputsURL: URL, outputsURL: URL) throws -> BatchRunSummary {
        let inputData = try Data(contentsOf: inputsURL)
        let jsonObject = try JSONSerialization.jsonObject(with: inputData, options: [])
        guard let rawEntries = jsonObject as? [Any] else {
            throw BatchExportError.invalidTopLevelJSON
        }

        var outputs: [BatchOutput] = []
        var failures = 0

        for rawEntry in rawEntries {
            guard let entry = rawEntry as? [String: Any] else {
                failures += 1
                continue
            }

            guard let id = nonEmptyString(entry["id"]),
                  let input = nonEmptyString(entry["input"])
            else {
                failures += 1
                continue
            }

            let viewModel = PromptEngineViewModel()
            viewModel.roughInput = input
            viewModel.forgePrompt()

            outputs.append(
                BatchOutput(
                id: id,
                input: input,
                currentOutput: viewModel.finalPrompt
            )
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let outputData = try encoder.encode(outputs)
        try ensureDirExists(outputsURL.deletingLastPathComponent())
        try outputData.write(to: outputsURL, options: .atomic)

        return BatchRunSummary(processedCount: outputs.count, failureCount: failures)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static let batchInputsTemplate = """
    [
      { "id": "IMG-001", "input": "Make an album cover with a red panda in a hoodie. Neon. Cool vibes." },
      { "id": "IMG-002", "input": "Portrait of a tired mechanic at 3am, cinematic." },
      { "id": "IMG-003", "input": "Character design sheet for a forest spirit: front/side/back views plus 3 expressions." },
      { "id": "IMG-004", "input": "Minimalist logo concept for 'Stinky Weasel Productions'." },
      { "id": "IMG-005", "input": "A sci-fi hallway: cool lighting, strong perspective, high detail without clutter." },
      { "id": "IMG-006", "input": "Photorealistic cat astronaut on Mars. Humor from pose/situation, not meme text." },
      { "id": "IMG-007", "input": "Fantasy map of an island kingdom with mountains, rivers, 3 settlements, 1 ruin. Keep geography logical." },
      { "id": "IMG-008", "input": "Cyberpunk street scene at night in rain: layered signage, one clear focal subject, readable silhouette." },

      { "id": "CODE-001", "input": "Write Python to batch-rename files by prefixing each filename with the file's modification date (YYYY-MM-DD). Include dry-run and safe mode." },
      { "id": "CODE-002", "input": "Create a React modal component: close on Escape, optional close on overlay click, focus trap, accessible attributes. No external UI libraries." },
      { "id": "CODE-003", "input": "Explain Docker volumes vs bind mounts for an intermediate developer. Include pitfalls and one short example for each. Under 500 words." },
      { "id": "CODE-004", "input": "Help debug why a function is slow. First ask for the minimum needed details, then give a profiling plan and hypotheses (clearly labeled)." },

      { "id": "PLAN-001", "input": "Plan a 3-day trip to Chicago. Cluster by neighborhood and include one rest block per day. Don't invent exact prices." },
      { "id": "PLAN-002", "input": "Create a workout plan. Ask for goals/equipment/limitations. Default to 3 days/week, 45–60 minutes. Include progression guidance." },
      { "id": "PLAN-003", "input": "Recommend a laptop for programming. Provide 3 tiers with tradeoffs. Do not invent current prices." },
      { "id": "PLAN-004", "input": "Make a simple weekly meal plan for one person on a budget. Include a short shopping list. Don’t assume dietary restrictions." },

      { "id": "WR-001", "input": "Write a short scene where two friends reconcile after a fight. Quiet, honest, not melodramatic. 600–900 words." },
      { "id": "WR-002", "input": "Write a manifesto about freedom: 5 short sections with headings. Each section: claim → concrete example → consequence. 900–1300 words." },
      { "id": "WR-003", "input": "Draft a professional email requesting a meeting. Include a subject line. Keep it under 120 words. Offer 2 time windows and ask them to choose." },
      { "id": "WR-004", "input": "Write a free-verse poem about grief: 18–28 lines, unsentimental, use concrete objects, avoid cliché metaphors, end on an image." }
    ]
    """
}
