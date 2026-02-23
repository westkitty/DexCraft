import XCTest

final class AnalyticsTests: XCTestCase {
    private let filename = "analytics-tests.json"

    func testRecordRunPersists() {
        let backend = InMemoryStorageBackend()
        let promptId = UUID()

        let repository = AnalyticsRepository(storageBackend: backend, filename: filename)
        repository.addRun(
            record: makeRecord(
                promptId: promptId,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                estimatedTokensInput: 3,
                estimatedTokensOutput: 5
            )
        )
        repository.addRun(
            record: makeRecord(
                promptId: promptId,
                timestamp: Date(timeIntervalSince1970: 1_700_000_100),
                estimatedTokensInput: 4,
                estimatedTokensOutput: 7
            )
        )

        let reloaded = AnalyticsRepository(storageBackend: backend, filename: filename)
        XCTAssertEqual(reloaded.listRuns(promptId: promptId).count, 2)
    }

    func testAggregationRunCount() {
        let backend = InMemoryStorageBackend()
        let promptId = UUID()
        let repository = AnalyticsRepository(storageBackend: backend, filename: filename)

        repository.addRun(record: makeRecord(promptId: promptId, estimatedTokensInput: 2, estimatedTokensOutput: 5))
        repository.addRun(record: makeRecord(promptId: promptId, estimatedTokensInput: 3, estimatedTokensOutput: 7))

        XCTAssertEqual(repository.runCount(promptId: promptId), 2)
    }

    func testTokenEstimatorDeterministic() {
        let backend = InMemoryStorageBackend()
        let promptId = UUID()
        let repository = AnalyticsRepository(storageBackend: backend, filename: filename)

        let input = "hello world"
        let estimatedInputTokens = TokenEstimator.estimate(for: input)
        XCTAssertEqual(estimatedInputTokens, 3)

        repository.addRun(
            record: PromptRunRecord(
                promptId: promptId,
                timestamp: Date(timeIntervalSince1970: 1_700_000_200),
                inputLengthChars: input.count,
                outputLengthChars: 4,
                estimatedTokensInput: estimatedInputTokens,
                estimatedTokensOutput: 1,
                adapterId: "local",
                durationMs: 10
            )
        )

        XCTAssertEqual(repository.listRuns(promptId: promptId).first?.estimatedTokensInput, 3)
    }

    func testAverageTokens() {
        let backend = InMemoryStorageBackend()
        let promptId = UUID()
        let repository = AnalyticsRepository(storageBackend: backend, filename: filename)

        repository.addRun(record: makeRecord(promptId: promptId, estimatedTokensInput: 2, estimatedTokensOutput: 5))
        repository.addRun(record: makeRecord(promptId: promptId, estimatedTokensInput: 2, estimatedTokensOutput: 7))

        XCTAssertEqual(repository.averageTokens(promptId: promptId), 6)
    }

    private func makeRecord(
        promptId: UUID,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        estimatedTokensInput: Int,
        estimatedTokensOutput: Int
    ) -> PromptRunRecord {
        PromptRunRecord(
            promptId: promptId,
            timestamp: timestamp,
            inputLengthChars: max(1, estimatedTokensInput * 4),
            outputLengthChars: max(1, estimatedTokensOutput * 4),
            estimatedTokensInput: estimatedTokensInput,
            estimatedTokensOutput: estimatedTokensOutput,
            adapterId: "local",
            durationMs: 42
        )
    }
}
