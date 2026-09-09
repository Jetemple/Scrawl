@testable import AudioCapture
import AVFoundation
import XCTest

final class CaptureDiagnosticsTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-diagnostics-\(UUID().uuidString)", isDirectory: true)
        setenv("SCRAWL_CAPTURE_DIAGNOSTICS", "1", 1)
        setenv("SCRAWL_CAPTURE_DIAGNOSTICS_DIR", directory.path, 1)
    }

    override func tearDown() {
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS")
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS_DIR")
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// The whole point of the log line is the gap between how long the microphone was open and
    /// how much audio came back, so that number has to be right on a file of known length.
    func testLogsGapBetweenWallClockAndRecordedAudio() throws {
        let audioURL = try makeSilentWAV(seconds: 5)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let id = try XCTUnwrap(CaptureDiagnostics.recordCapture(
            audioURL: audioURL,
            wallSeconds: 8,
            recorderSeconds: 5.01
        ))

        let line = try XCTUnwrap(readLog().first { $0.contains("capture=\(id)") })
        XCTAssertTrue(line.contains("wall=8.00s"), line)
        XCTAssertTrue(line.contains("recorder=5.01s"), line)
        XCTAssertTrue(line.contains("file=5.00s"), line)
        XCTAssertTrue(line.contains("missing=3.00s"), line)
    }

    /// The saved copy is the only artifact left to replay once the finalize path deletes the
    /// working file, so it has to be a real, readable recording of the same length.
    func testKeepsAPlayableCopyOfTheRecording() throws {
        let audioURL = try makeSilentWAV(seconds: 2)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let id = try XCTUnwrap(CaptureDiagnostics.recordCapture(
            audioURL: audioURL,
            wallSeconds: 2,
            recorderSeconds: 2
        ))

        let copy = directory.appendingPathComponent("capture-\(id).wav")
        let file = try AVAudioFile(forReading: copy)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 2, accuracy: 0.01)
    }

    func testLogsRejectedRecordingsSoTheyAreNotSilentlyAbsent() throws {
        CaptureDiagnostics.recordRejection(
            wallSeconds: 4.5,
            error: AudioCaptureError.audioLevelTooLow
        )

        let line = try XCTUnwrap(readLog().first { $0.contains("rejected=") })
        XCTAssertTrue(line.contains("wall=4.50s"), line)
        XCTAssertTrue(line.contains("audioLevelTooLow"), line)
    }

    func testLogsHotkeyTransitionsWithBothSourcesSeparately() throws {
        setenv("SCRAWL_CAPTURE_DIAGNOSTICS", "1", 1)

        // The two sources are ORed into one decision in the monitor, so they are logged apart:
        // a release the flag reports but keyState contradicts is the shape of a spurious stop.
        CaptureDiagnostics.recordHotkeyTransition(isDown: true, flag: true, keyState: true)
        CaptureDiagnostics.recordHotkeyTransition(isDown: false, flag: false, keyState: false)

        let log = try String(contentsOf: directory.appendingPathComponent("capture-diagnostics.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("hotkey=down") && log.contains("flag=true keyState=true"), log)
        XCTAssertTrue(log.contains("hotkey=up") && log.contains("flag=false keyState=false"), log)
    }

    func testWritesNothingWhenDisabled() throws {
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS")
        let audioURL = try makeSilentWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        XCTAssertNil(CaptureDiagnostics.recordCapture(audioURL: audioURL, wallSeconds: 1, recorderSeconds: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testConcurrentEventsProduceCompleteLogLines() throws {
        let iterations = 100
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            CaptureDiagnostics.recordHotkeyTransition(
                isDown: index.isMultiple(of: 2),
                flag: true,
                keyState: false
            )
        }

        let lines = try readLog()
        XCTAssertEqual(lines.count, iterations)
        XCTAssertTrue(lines.allSatisfy {
            $0.contains("hotkey=") && $0.contains(" at=")
                && $0.contains(" flag=true keyState=false")
        })
    }

    private func readLog() throws -> [String] {
        let logURL = directory.appendingPathComponent("capture-diagnostics.log")
        return try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    private func makeSilentWAV(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-diagnostics-test-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(seconds * 16000)
        // Buffers handed to AVAudioFile must match its processing format, not the file's
        // on-disk encoding — an Int16 buffer against the default Float32 processing format traps.
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }
}
