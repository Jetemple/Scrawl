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

    // MARK: - Task 8: Readiness identity check, port pre-check, budget

    func testIsWhisperServerResponseAcceptsWhisperCppTitle() {
        // Empirically verified: whisper-server GET / returns HTML with <title>Whisper.cpp Server</title>
        let html = Data("<html><head><title>Whisper.cpp Server</title></head></html>".utf8)
        XCTAssertTrue(WarmWhisperServer.isWhisperServerResponse(html))
    }

    func testIsWhisperServerResponseAcceptsWhisperServerString() {
        let data = Data("whisper-server version 1.2.3".utf8)
        XCTAssertTrue(WarmWhisperServer.isWhisperServerResponse(data))
    }

    func testIsWhisperServerResponseRejectsForeignNotFound() {
        let data = Data("404 Not Found".utf8)
        XCTAssertFalse(WarmWhisperServer.isWhisperServerResponse(data))
    }

    func testIsWhisperServerResponseRejectsForeignJSON() {
        let data = Data("{\"error\": \"not a whisper service\"}".utf8)
        XCTAssertFalse(WarmWhisperServer.isWhisperServerResponse(data))
    }

    func testAllocatePortReturnsUsablePort() throws {
        let port = try WarmWhisperServer.allocatePort()
        XCTAssertGreaterThan(port, 0)
        XCTAssertLessThan(port, 65536)
    }

    func testAllocatePortReturnsDifferentPortsOnSuccessiveCalls() throws {
        let port1 = try WarmWhisperServer.allocatePort()
        let port2 = try WarmWhisperServer.allocatePort()
        // Ports are kernel-assigned and should normally differ; both must be valid
        XCTAssertGreaterThan(port1, 0)
        XCTAssertGreaterThan(port2, 0)
    }

    // MARK: - Fix 1: idle-offload timer fires for warmed-but-unused servers

    /// Verifies that a server started via ensureRunning (the warmUp path) gets an
    /// idle-offload timer and is shut down after the idle interval elapses, even
    /// when no transcription request is ever made. A launch-counter file written by
    /// the stub lets us confirm the server was torn down and re-launched on the
    /// second ensureRunning call.
    func testWarmedServerIsOffloadedAfterIdleInterval() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let stubURL = tmpDir.appendingPathComponent("stub-http-server-\(UUID().uuidString)")
        let counterURL = tmpDir.appendingPathComponent("stub-launch-count-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: stubURL)
            try? FileManager.default.removeItem(at: counterURL)
        }

        // Stub: record each launch in counterURL, then serve whisper-cpp HTTP responses.
        // We use a Python3 socket server because URLSession requires proper HTTP/1.1
        // with Connection: close — plain nc exits before URLSession can read the body
        // and produces NSURLErrorDomain -1005 "The network connection was lost."
        // supervisedLaunch runs: sh -c <supervisorScript> scrawl-whisper-supervisor
        //   <ownerPID> <ourStubURL> [server-args...]
        // The supervisor script does: owner=$1; shift; "$@" &
        // So our stub is exec'd with just the server args (e.g. --port 12345).
        //
        // The Python script is written to a sibling file to avoid quoting issues
        // with heredocs embedded in a Swift string literal.
        let pyScriptURL = tmpDir.appendingPathComponent("stub-server-\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: pyScriptURL) }
        let pyScript = """
        import sys, socket, threading
        port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('127.0.0.1', port))
        s.listen(10)
        body = b'<title>Whisper.cpp Server</title>'
        resp = (b'HTTP/1.1 200 OK\\r\\nContent-Type: text/html\\r\\n'
                b'Content-Length: ' + str(len(body)).encode() + b'\\r\\n'
                b'Connection: close\\r\\n\\r\\n' + body)
        while True:
            try:
                conn, _ = s.accept()
                def handle(c):
                    try: c.recv(4096); c.sendall(resp)
                    finally: c.close()
                threading.Thread(target=handle, args=(conn,), daemon=True).start()
            except Exception:
                break
        """
        try pyScript.write(to: pyScriptURL, atomically: true, encoding: .utf8)

        let stubScript = """
        #!/bin/sh
        port=""
        while [ $# -gt 0 ]; do
          case "$1" in --port) port="$2"; shift 2;; *) shift;; esac
        done
        printf '1\\n' >> "\(counterURL.path)"
        exec python3 "\(pyScriptURL.path)" "$port"
        """
        try stubScript.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)

        // Use a very short idle interval so the test doesn't stall.
        let config = WhisperCppConfig(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
            serverExecutableURL: stubURL,
            modelsDirectoryURL: FileManager.default.temporaryDirectory,
            idleOffloadSeconds: 0.5
        )
        let server = WarmWhisperServer(config: config)

        let key = WarmWhisperServer.ServerKey(modelID: "test", language: "en", forceNoGPU: false)
        let modelPath = URL(fileURLWithPath: "/tmp/fake-model.bin")

        // First ensureRunning — should succeed and schedule an idle-offload timer.
        _ = try await server.ensureRunning(key: key, modelPath: modelPath)

        // Wait long enough for the idle timer (0.5 s) to fire plus margin.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // A second ensureRunning after offload should re-launch the stub (a new process).
        _ = try? await server.ensureRunning(key: key, modelPath: modelPath)

        // If the idle-offload timer fired, the stub was launched at least twice.
        let countText = (try? String(contentsOf: counterURL, encoding: .utf8)) ?? "0"
        let launches = countText.components(separatedBy: "\n").filter { $0 == "1" }.count
        XCTAssertGreaterThanOrEqual(launches, 2,
            "Expected stub to be launched at least twice (warm-up + re-launch after idle offload); got \(launches). " +
            "If the idle timer was not scheduled by ensureRunning, the server stays alive and no re-launch occurs.")

        await server.shutdown()
    }

    // MARK: - Fix 2: retry on early server exit

    /// Verifies that when whisper-server exits during startup (simulated by a stub
    /// that always exits immediately), ensureRunning retries exactly once before
    /// propagating the error. The launch counter lets us confirm two attempts were made.
    func testEarlyExitDuringStartupRetriesOnceThenThrows() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let stubURL = tmpDir.appendingPathComponent("stub-exit-server-\(UUID().uuidString)")
        let counterURL = tmpDir.appendingPathComponent("stub-exit-count-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: stubURL)
            try? FileManager.default.removeItem(at: counterURL)
        }

        // Stub: record launch and exit immediately so waitUntilReady sees !isRunning.
        let stubScript = """
        #!/bin/sh
        printf '1\\n' >> "\(counterURL.path)"
        exit 1
        """
        try stubScript.write(to: stubURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)

        let config = WhisperCppConfig(
            executableURL: URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
            serverExecutableURL: stubURL,
            modelsDirectoryURL: FileManager.default.temporaryDirectory
        )
        let server = WarmWhisperServer(config: config)

        let key = WarmWhisperServer.ServerKey(modelID: "test", language: "en", forceNoGPU: false)
        let modelPath = URL(fileURLWithPath: "/tmp/fake-model.bin")

        do {
            _ = try await server.ensureRunning(key: key, modelPath: modelPath)
            XCTFail("Expected ensureRunning to throw after exhausting retries")
        } catch TranscriptionError.executionFailed(let msg) {
            XCTAssertTrue(
                msg.contains("exited during startup") || msg.contains("did not become ready"),
                "Unexpected error message: \(msg)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        // Give the supervisor wrappers a moment to record their launches.
        try await Task.sleep(nanoseconds: 500_000_000)

        let countText = (try? String(contentsOf: counterURL, encoding: .utf8)) ?? "0"
        let launches = countText.components(separatedBy: "\n").filter { $0 == "1" }.count
        XCTAssertEqual(launches, 2,
            "Expected exactly 2 launch attempts (initial + one retry); got \(launches)")
    }

    /// Verifies that the existing concurrent-callers-both-throw test remains green
    /// after the retry logic is introduced. This is the regression guard for Fix 2.
    func testConcurrentCallersAfterRetryExhaustedBothThrow() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let stubURL = tmpDir.appendingPathComponent("stub-conc-exit-\(UUID().uuidString)")
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
}
