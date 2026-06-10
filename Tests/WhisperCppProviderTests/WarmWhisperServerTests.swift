import XCTest
@testable import WhisperCppProvider
import Foundation
import TranscriptionCore

final class WarmWhisperServerTests: XCTestCase {

    // MARK: - Moved from WhisperCppPostProcessingTests

    func testWarmServerLaunchIsSupervisedByOwnerProcess() {
        let launch = WarmWhisperServer.supervisedLaunch(
            serverExecutableURL: URL(filePath: "/opt/homebrew/bin/whisper-server"),
            serverArguments: ["--port", "18432"],
            ownerPID: 1234
        )

        XCTAssertEqual(launch.executableURL, URL(filePath: "/bin/sh"))
        XCTAssertTrue(launch.arguments.contains("1234"))
        XCTAssertTrue(launch.arguments.contains("/opt/homebrew/bin/whisper-server"))
        XCTAssertTrue(launch.arguments.joined(separator: " ").contains("kill \"$child\""))
    }

    // MARK: - Task 4: Reentrancy

    func testConcurrentEnsureRunningBothThrowWhenServerExitsImmediately() async throws {
        // Create a stub executable that exits immediately
        let tmpDir = FileManager.default.temporaryDirectory
        let stubURL = tmpDir.appendingPathComponent("stub-server-\(UUID().uuidString)")
        let stubScript = "#!/bin/sh\nexit 1\n"
        try stubScript.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)
        defer { try? FileManager.default.removeItem(at: stubURL) }

        let config = WhisperCppConfig(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
            serverExecutableURL: stubURL,
            modelsDirectoryURL: FileManager.default.temporaryDirectory
        )
        let server = WarmWhisperServer(config: config)

        let key = WarmWhisperServer.ServerKey(modelID: "test", language: "en", forceNoGPU: false)
        let modelPath = URL(fileURLWithPath: "/tmp/fake-model.bin")

        async let result1: URL = server.ensureRunning(key: key, modelPath: modelPath)
        async let result2: URL = server.ensureRunning(key: key, modelPath: modelPath)

        do {
            _ = try await result1
            XCTFail("Expected first call to throw")
        } catch {}
        do {
            _ = try await result2
            XCTFail("Expected second call to throw")
        } catch {}
    }

    // MARK: - Task 5: Warm path fallback decision

    func testNoSpeechDetectedRethrownNotShutdown() {
        XCTAssertEqual(
            WhisperCppProvider.warmPathFallbackDecision(for: TranscriptionError.noSpeechDetected),
            .rethrow
        )
    }

    func testTimedOutRethrownNotShutdown() {
        XCTAssertEqual(
            WhisperCppProvider.warmPathFallbackDecision(for: TranscriptionError.timedOut(seconds: 30)),
            .rethrow
        )
    }

    func testCancellationErrorRethrownNotShutdown() {
        XCTAssertEqual(
            WhisperCppProvider.warmPathFallbackDecision(for: CancellationError()),
            .rethrow
        )
    }

    func testURLErrorCannotConnectTriggersShutdownAndFallback() {
        XCTAssertEqual(
            WhisperCppProvider.warmPathFallbackDecision(for: URLError(.cannotConnectToHost)),
            .shutdownAndFallback
        )
    }

    func testExecutionFailedTriggersShutdownAndFallback() {
        XCTAssertEqual(
            WhisperCppProvider.warmPathFallbackDecision(for: TranscriptionError.executionFailed("crash")),
            .shutdownAndFallback
        )
    }

    // MARK: - Task 7: SIGKILL escalation

    func testRunAndWaitKillsSIGTERMIgnoringProcess() async throws {
        let provider = WhisperCppProvider(config: WhisperCppConfig(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
            modelsDirectoryURL: FileManager.default.temporaryDirectory
        ))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; sleep 30"]

        do {
            _ = try await provider.runAndWait(process: process, timeoutSeconds: 1)
            XCTFail("Expected timedOut error")
        } catch TranscriptionError.timedOut(let seconds) {
            XCTAssertEqual(seconds, 1)
        }
        // Process should be dead within a few seconds after SIGKILL
        try await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertFalse(process.isRunning, "Process should have been killed by SIGKILL")
    }
}
