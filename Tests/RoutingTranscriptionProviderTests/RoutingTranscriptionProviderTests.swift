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

    func testWarmUpRoutesToSelectedEngineAndShutdownCoversBothEngines() async {
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
        XCTAssertEqual(parakeet.idleOffloadSeconds, 7)
        XCTAssertEqual(whisper.idleOffloadSeconds, 7)
        XCTAssertEqual(parakeet.shutdownCount, 1)
        XCTAssertEqual(whisper.shutdownCount, 1)
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
    private var _idleOffloadSeconds: TimeInterval?
    private var _shutdownCount = 0

    init(resultText: String) {
        self.resultText = resultText
    }

    var transcribeModelIDs: [String] {
        lock.withLock { _transcribeModelIDs }
    }

    var warmUpModelIDs: [String] {
        lock.withLock { _warmUpModelIDs }
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

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
