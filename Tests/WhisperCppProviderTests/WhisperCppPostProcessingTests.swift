import XCTest
@testable import WhisperCppProvider
import TranscriptionCore

final class WhisperCppPostProcessingTests: XCTestCase {
    func testBlankAudioMarkerIsTreatedAsNoSpeech() {
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("[BLANK_AUDIO]"))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript(" [ no_speech ] "))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("[MUSIC]\n[NOISE]"))
    }

    func testNormalTranscriptIsNotTreatedAsNoSpeech() {
        XCTAssertFalse(WhisperCppProvider.isNoSpeechTranscript("Hello this is a test"))
    }

    func testBareNoiseWordsAreNotTreatedAsNoSpeech() {
        XCTAssertFalse(WhisperCppProvider.isNoSpeechTranscript("Music"))
        XCTAssertFalse(WhisperCppProvider.isNoSpeechTranscript("Noise"))
    }

    func testCommonNoInputGhostTranscriptsAreTreatedAsNoSpeech() {
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("you"))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("You."))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("-"))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("—"))
    }

    func testTimeoutIsNotRetriedOnCPU() {
        // A timeout means the run was too slow, not that the GPU is broken. Re-running the same
        // long input on CPU is typically slower and can time out again (~2x the stall), so a
        // timeout must fail fast to the user instead of triggering a CPU fallback.
        XCTAssertFalse(WhisperCppProvider.isRetryableWithCPU(error: .timedOut(seconds: 120), forceNoGPU: false))
    }

    func testGenuineExecutionFailureIsRetriedOnCPU() {
        XCTAssertTrue(WhisperCppProvider.isRetryableWithCPU(error: .executionFailed("metal error"), forceNoGPU: false))
    }

    func testNoRetryWhenAlreadyForcedToCPU() {
        XCTAssertFalse(WhisperCppProvider.isRetryableWithCPU(error: .executionFailed("metal error"), forceNoGPU: true))
    }

    func testNonExecutionErrorsAreNotRetriedOnCPU() {
        XCTAssertFalse(WhisperCppProvider.isRetryableWithCPU(error: .noSpeechDetected, forceNoGPU: false))
        XCTAssertFalse(WhisperCppProvider.isRetryableWithCPU(error: .modelMissing("ggml-small.en"), forceNoGPU: false))
    }

    func testMakeCLIArgumentsIncludesThreadsAndNoGPUWhenConfigured() {
        let config = WhisperCppConfig(
            executableURL: URL(filePath: "/usr/local/bin/whisper-cli"),
            modelsDirectoryURL: URL(filePath: "/tmp/models"),
            disableGPU: true,
            threads: 6
        )
        let provider = WhisperCppProvider(config: config)
        let request = TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/input.wav"),
            modelID: "ggml-small.en",
            language: "en"
        )
        let arguments = provider.makeCLIArguments(
            request: request,
            modelPath: URL(filePath: "/tmp/models/ggml-small.en.bin"),
            outputPrefix: URL(filePath: "/tmp/output")
        )

        XCTAssertTrue(arguments.contains("--no-gpu"))
        XCTAssertTrue(arguments.contains("-t"))

        if let threadFlagIndex = arguments.firstIndex(of: "-t") {
            XCTAssertEqual(arguments[threadFlagIndex + 1], "6")
        } else {
            XCTFail("Expected thread flag in whisper-cli arguments")
        }
    }

    func testMakeCLIArgumentsOmitsOptionalPerformanceFlagsWhenNotConfigured() {
        let config = WhisperCppConfig(
            executableURL: URL(filePath: "/usr/local/bin/whisper-cli"),
            modelsDirectoryURL: URL(filePath: "/tmp/models"),
            disableGPU: false,
            threads: nil
        )
        let provider = WhisperCppProvider(config: config)
        let request = TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/input.wav"),
            modelID: "ggml-small.en",
            language: "en"
        )
        let arguments = provider.makeCLIArguments(
            request: request,
            modelPath: URL(filePath: "/tmp/models/ggml-small.en.bin"),
            outputPrefix: URL(filePath: "/tmp/output")
        )

        XCTAssertFalse(arguments.contains("--no-gpu"))
        XCTAssertFalse(arguments.contains("-t"))
    }

    func testMakeCLIArgumentsIncludesNoGPUWhenForcedByRuntimeFallback() {
        let config = WhisperCppConfig(
            executableURL: URL(filePath: "/usr/local/bin/whisper-cli"),
            modelsDirectoryURL: URL(filePath: "/tmp/models"),
            disableGPU: false,
            threads: nil
        )
        let provider = WhisperCppProvider(config: config)
        let request = TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/input.wav"),
            modelID: "ggml-small.en",
            language: "en"
        )
        let arguments = provider.makeCLIArguments(
            request: request,
            modelPath: URL(filePath: "/tmp/models/ggml-small.en.bin"),
            outputPrefix: URL(filePath: "/tmp/output"),
            forceNoGPU: true
        )

        XCTAssertTrue(arguments.contains("--no-gpu"))
    }
}
