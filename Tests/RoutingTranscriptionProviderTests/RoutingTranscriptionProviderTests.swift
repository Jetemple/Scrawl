import Foundation
@testable import ParakeetProvider
import TranscriptionCore
import XCTest

final class RoutingTranscriptionProviderTests: XCTestCase {
    func testParakeetModelIDRoutesToParakeetProvider() async throws {
        let whisper = SpyModelRetainingProvider(resultText: "whisper")
        let parakeet = SpyModelRetainingProvider(resultText: "parakeet")
        let router = RoutingTranscriptionProvider(
            whisperProvider: whisper,
            parakeetProvider: parakeet
        )

        let result = try await router.transcribe(request(modelID: TranscriptionModelID.parakeetV3))

        XCTAssertEqual(result.text, "parakeet")
        XCTAssertEqual(whisper.transcribeModelIDs, [])
        XCTAssertEqual(parakeet.transcribeModelIDs, [TranscriptionModelID.parakeetV3])
    }

    func testWhisperModelIDRoutesToWhisperProvider() async throws {
        let whisper = SpyModelRetainingProvider(resultText: "whisper")
        let parakeet = SpyModelRetainingProvider(resultText: "parakeet")
        let router = RoutingTranscriptionProvider(
            whisperProvider: whisper,
            parakeetProvider: parakeet
        )

        let result = try await router.transcribe(request(modelID: "ggml-small.en"))

        XCTAssertEqual(result.text, "whisper")
        XCTAssertEqual(whisper.transcribeModelIDs, ["ggml-small.en"])
        XCTAssertEqual(parakeet.transcribeModelIDs, [])
    }

    func testParakeetModelIDFallsBackToWhisperWhenParakeetProviderIsUnavailable() async throws {
        let whisper = SpyModelRetainingProvider(resultText: "whisper")
        let router = RoutingTranscriptionProvider(
            whisperProvider: whisper,
            parakeetProvider: nil
        )

        let result = try await router.transcribe(request(modelID: TranscriptionModelID.parakeetV3))

        XCTAssertEqual(result.text, "whisper")
        XCTAssertEqual(whisper.transcribeModelIDs, [TranscriptionModelID.parakeetV3])
    }

    func testWarmUpRoutesToSelectedEngineKeepsParakeetWarmAndShutdownCoversBothEngines() async {
        let whisper = SpyModelRetainingProvider(resultText: "whisper")
        let parakeet = SpyModelRetainingProvider(resultText: "parakeet")
        let router = RoutingTranscriptionProvider(
            whisperProvider: whisper,
            parakeetProvider: parakeet
        )

        await router.warmUp(modelID: TranscriptionModelID.parakeetV3, language: "en")
        await router.warmUp(modelID: "ggml-small.en", language: "en")
        await router.setIdleOffloadSeconds(7)
        await router.shutdown()

        XCTAssertEqual(parakeet.warmUpModelIDs, [TranscriptionModelID.parakeetV3])
        XCTAssertEqual(whisper.warmUpModelIDs, ["ggml-small.en"])
        XCTAssertNil(parakeet.idleOffloadSeconds)
        XCTAssertEqual(whisper.idleOffloadSeconds, 7)
        XCTAssertEqual(parakeet.shutdownCount, 1)
        XCTAssertEqual(whisper.shutdownCount, 1)
    }

    func testTargetedShutdownForWhisperModelDoesNotShutdownParakeet() async {
        let whisper = SpyModelRetainingProvider(resultText: "whisper")
        let parakeet = SpyModelRetainingProvider(resultText: "parakeet")
        let router = RoutingTranscriptionProvider(
            whisperProvider: whisper,
            parakeetProvider: parakeet
        )

        await router.shutdown(modelID: "ggml-large-v3-turbo")

        XCTAssertEqual(whisper.shutdownCount, 1)
        XCTAssertEqual(parakeet.shutdownCount, 0)
    }

    func testPrepareModelRoutesParakeetProgress() async throws {
        let whisper = SpyModelRetainingProvider(resultText: "whisper")
        let parakeet = SpyModelRetainingProvider(resultText: "parakeet")
        parakeet.preparationProgress = ModelPreparationProgress(
            fractionCompleted: 0.42,
            phase: .downloading
        )
        let router = RoutingTranscriptionProvider(
            whisperProvider: whisper,
            parakeetProvider: parakeet
        )

        let progressRecorder = ProgressRecorder()
        try await router.prepareModel(
            modelID: TranscriptionModelID.parakeetV3,
            language: "en",
            progressHandler: { progress in
                progressRecorder.append(progress)
            }
        )

        XCTAssertEqual(parakeet.prepareModelIDs, [TranscriptionModelID.parakeetV3])
        XCTAssertEqual(whisper.prepareModelIDs, [])
        XCTAssertEqual(progressRecorder.events, [ModelPreparationProgress(fractionCompleted: 0.42, phase: .downloading)])
    }

    private func request(modelID: String) -> TranscriptionRequest {
        TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/audio.wav"),
            modelID: modelID,
            language: "en"
        )
    }
}

private final class SpyModelRetainingProvider: ModelRetainingTranscriptionProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let resultText: String
    private var _transcribeModelIDs: [String] = []
    private var _warmUpModelIDs: [String] = []
    private var _prepareModelIDs: [String] = []
    private var _idleOffloadSeconds: TimeInterval?
    private var _shutdownCount = 0
    var preparationProgress: ModelPreparationProgress?

    init(resultText: String) {
        self.resultText = resultText
    }

    var transcribeModelIDs: [String] {
        lock.withLock { _transcribeModelIDs }
    }

    var warmUpModelIDs: [String] {
        lock.withLock { _warmUpModelIDs }
    }

    var prepareModelIDs: [String] {
        lock.withLock { _prepareModelIDs }
    }

    var idleOffloadSeconds: TimeInterval? {
        lock.withLock { _idleOffloadSeconds }
    }

    var shutdownCount: Int {
        lock.withLock { _shutdownCount }
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        lock.withLock {
            _transcribeModelIDs.append(request.modelID)
        }
        return TranscriptionResult(text: resultText, latencyMS: 1)
    }

    func warmUp(modelID: String, language _: String) async {
        lock.withLock {
            _warmUpModelIDs.append(modelID)
        }
    }

    func prepareModel(
        modelID: String,
        language _: String,
        progressHandler: ModelPreparationProgressHandler?
    ) async throws {
        lock.withLock {
            _prepareModelIDs.append(modelID)
        }
        if let preparationProgress {
            progressHandler?(preparationProgress)
        }
    }

    func setIdleOffloadSeconds(_ seconds: TimeInterval?) async {
        lock.withLock {
            _idleOffloadSeconds = seconds
        }
    }

    func shutdown() async {
        lock.withLock {
            _shutdownCount += 1
        }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [ModelPreparationProgress] = []

    var events: [ModelPreparationProgress] {
        lock.withLock { _events }
    }

    func append(_ event: ModelPreparationProgress) {
        lock.withLock {
            _events.append(event)
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
