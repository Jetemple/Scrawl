import XCTest
@testable import WhisperCppProvider
import Foundation
import TranscriptionCore

final class WhisperCppPostProcessingTests: XCTestCase {
    func testMissingWarmServerFallsBackToCLI() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "scrawl-provider-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cli = directory.appending(path: "whisper-cli")
        let script = """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-of" ]; then
            shift
            output="$1"
          fi
          shift
        done
        printf 'CLI fallback transcript\\n' > "${output}.txt"
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        try Data().write(to: directory.appending(path: "ggml-small.en.bin"))
        let audio = directory.appending(path: "audio.wav")
        try Data().write(to: audio)

        let provider = WhisperCppProvider(config: WhisperCppConfig(
            executableURL: cli,
            serverExecutableURL: directory.appending(path: "missing-whisper-server"),
            modelsDirectoryURL: directory
        ))

        let result = try await provider.transcribe(
            TranscriptionRequest(audioFileURL: audio, modelID: "ggml-small.en")
        )

        XCTAssertEqual(result.text, "CLI fallback transcript")
    }

    func testLiveWarmServerTranscribesWhenLocalFixturesAreAvailable() async throws {
        guard ProcessInfo.processInfo.environment["SCRAWL_RUN_LOCAL_PERF_TESTS"] == "1" else {
            throw XCTSkip("Local whisper.cpp performance fixture test is opt-in")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let model = home.appending(path: "Library/Application Support/Scrawl/models/ggml-small.en.bin")
        let audio = URL(filePath: "/opt/homebrew/Cellar/whisper-cpp/1.8.6/share/whisper-cpp/jfk.wav")
        let cli = URL(filePath: "/opt/homebrew/bin/whisper-cli")
        guard FileManager.default.fileExists(atPath: model.path),
              FileManager.default.fileExists(atPath: audio.path),
              FileManager.default.isExecutableFile(atPath: cli.path) else {
            throw XCTSkip("Local whisper.cpp performance fixtures are unavailable")
        }

        let provider = WhisperCppProvider(config: WhisperCppConfig(
            executableURL: cli,
            modelsDirectoryURL: model.deletingLastPathComponent(),
            threads: 8,
            idleOffloadSeconds: 300
        ))
        await provider.warmUp(modelID: "ggml-small.en", language: "en")
        let request = TranscriptionRequest(audioFileURL: audio, modelID: "ggml-small.en")

        let first = try await provider.transcribe(request)
        let second = try await provider.transcribe(request)
        await provider.shutdown()

        XCTAssertTrue(first.text.contains("fellow Americans"))
        XCTAssertTrue(second.text.contains("fellow Americans"))
        XCTAssertLessThan(second.latencyMS, 1_000)
    }

    func testServerExecutableResolvesBesideCLI() {
        XCTAssertEqual(
            WhisperCppProvider.serverExecutableURL(
                forCLI: URL(filePath: "/opt/homebrew/bin/whisper-cli")
            ),
            URL(filePath: "/opt/homebrew/bin/whisper-server")
        )
    }

    func testServerArgumentsBindLoopbackAndIncludePerformanceConfiguration() {
        let provider = WhisperCppProvider(config: WhisperCppConfig(
            executableURL: URL(filePath: "/usr/local/bin/whisper-cli"),
            modelsDirectoryURL: URL(filePath: "/tmp/models"),
            disableGPU: true,
            threads: 6
        ))

        let arguments = provider.makeServerArguments(
            modelPath: URL(filePath: "/tmp/models/ggml-small.en.bin"),
            language: "en",
            port: 18432,
            forceNoGPU: true
        )

        XCTAssertTrue(arguments.contains("--host"))
        XCTAssertTrue(arguments.contains("127.0.0.1"))
        XCTAssertTrue(arguments.contains("--port"))
        XCTAssertTrue(arguments.contains("18432"))
        XCTAssertTrue(arguments.contains("-bo"))
        XCTAssertTrue(arguments.contains("-bs"))
        XCTAssertTrue(arguments.contains("--no-gpu"))
        XCTAssertTrue(arguments.contains("-t"))
        XCTAssertTrue(arguments.contains("6"))
    }

    func testServerResponseDecodesTranscriptText() throws {
        let data = Data(#"{"text":" Hello from warm Whisper.\n"}"#.utf8)

        XCTAssertEqual(try WhisperCppProvider.decodeServerTranscript(data), "Hello from warm Whisper.")
    }

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

    func testBareTheArticleHallucinationIsTreatedAsNoSpeech() {
        // "The" is whisper's classic short-clip hallucination on ambient noise
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("The"))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript("the."))
        XCTAssertTrue(WhisperCppProvider.isNoSpeechTranscript(" The "))
    }

    func testSentenceStartingWithTheIsNotFilteredAsNoSpeech() {
        XCTAssertFalse(WhisperCppProvider.isNoSpeechTranscript("The quick brown fox"))
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

    func testMakeCLIArgumentsIncludesNonEmptyPromptContext() {
        let provider = WhisperCppProvider(config: WhisperCppConfig(
            executableURL: URL(filePath: "/usr/local/bin/whisper-cli"),
            modelsDirectoryURL: URL(filePath: "/tmp/models")
        ))
        let request = TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/input.wav"),
            modelID: "ggml-small.en",
            promptContext: "Preferred vocabulary: Anduril, Postgres"
        )

        let arguments = provider.makeCLIArguments(
            request: request,
            modelPath: URL(filePath: "/tmp/models/ggml-small.en.bin"),
            outputPrefix: URL(filePath: "/tmp/output")
        )

        XCTAssertEqual(arguments.suffix(2), ["--prompt", "Preferred vocabulary: Anduril, Postgres"])
    }

    func testMakeCLIArgumentsOmitsBlankPromptContext() {
        let provider = WhisperCppProvider(config: WhisperCppConfig(
            executableURL: URL(filePath: "/usr/local/bin/whisper-cli"),
            modelsDirectoryURL: URL(filePath: "/tmp/models")
        ))
        let request = TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/input.wav"),
            modelID: "ggml-small.en",
            promptContext: "  \n "
        )

        let arguments = provider.makeCLIArguments(
            request: request,
            modelPath: URL(filePath: "/tmp/models/ggml-small.en.bin"),
            outputPrefix: URL(filePath: "/tmp/output")
        )

        XCTAssertFalse(arguments.contains("--prompt"))
    }

    func testTranscriptionRequestCarriesOptionalProgressHandler() {
        let request = TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/input.wav"),
            modelID: "ggml-large-v3-turbo",
            language: "en",
            progressHandler: { _ in }
        )

        XCTAssertNotNil(request.progressHandler)
    }

    func testTranscriptionRequestCarriesOptionalPromptContext() {
        let request = TranscriptionRequest(
            audioFileURL: URL(filePath: "/tmp/input.wav"),
            modelID: "ggml-large-v3-turbo",
            promptContext: "Preferred vocabulary: Anduril"
        )

        XCTAssertEqual(request.promptContext, "Preferred vocabulary: Anduril")
    }

    func testProgressPhaseDetectsWhisperProcessingLogLine() {
        let line = "main: processing '/tmp/input.wav' (16000 samples, 1.0 sec), 8 threads, 8 processors, 1 beams + best of 5, lang = en, task = transcribe, timestamps = 0 ..."

        XCTAssertEqual(WhisperCppProvider.progressPhase(forCLIOutput: line), .transcribing)
        XCTAssertNil(WhisperCppProvider.progressPhase(forCLIOutput: "system_info: n_threads = 8 / 8"))
    }
}
