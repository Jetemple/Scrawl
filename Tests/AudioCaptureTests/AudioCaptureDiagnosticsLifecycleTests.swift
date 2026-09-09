@testable import AudioCapture
import AVFoundation
import Foundation
import XCTest

/// Two-stage event-policy tests: production finish/analysis/compatibility hooks must emit
/// exact capture/rejection counts and consume URL-keyed wall metadata exactly once.
/// `completeFinishCapture` / `verifyCompatibilityCapture` are the same helpers the real
/// `finishCapture()` / `stopCapture()` call, so these tests exercise production policy
/// without requiring microphone permission.
final class AudioCaptureDiagnosticsLifecycleTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-lifecycle-\(UUID().uuidString)", isDirectory: true)
        setenv("SCRAWL_CAPTURE_DIAGNOSTICS", "1", 1)
        setenv("SCRAWL_CAPTURE_DIAGNOSTICS_DIR", directory.path, 1)
    }

    override func tearDown() {
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS")
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS_DIR")
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testFinishedCaptureWallTimeIsAvailableExactlyOnce() {
        let service = AudioCaptureService()
        let url = URL(fileURLWithPath: "/tmp/capture-once.wav")

        service.storeDiagnosticWallSecondsIfEnabled(3.25, for: url)

        XCTAssertEqual(service.takeDiagnosticWallSeconds(for: url), 3.25)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
    }

    func testDisabledDiagnosticsDoNotRetainFinishedCaptureMetadata() {
        unsetenv("SCRAWL_CAPTURE_DIAGNOSTICS")
        let service = AudioCaptureService()
        let url = URL(fileURLWithPath: "/tmp/capture-disabled.wav")

        service.storeDiagnosticWallSecondsIfEnabled(3.25, for: url)

        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
    }

    func testFinishSuccessStoresWallTimeAndRecordsCaptureOnce() throws {
        let service = AudioCaptureService()
        let url = try makeLoudWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let returned = try service.completeFinishCapture(at: url, recorderSeconds: 1.0, wallSeconds: 2.5)
        XCTAssertEqual(returned, url)

        XCTAssertEqual(captureLines().count, 1)
        XCTAssertEqual(rejectionLines().count, 0)
        // Stored exactly once: first take returns the wall time, second returns nil.
        XCTAssertEqual(try XCTUnwrap(service.takeDiagnosticWallSeconds(for: url)), 2.5, accuracy: 0.001)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testFinishDurationRejectionRecordsOnlyRejection() throws {
        let service = AudioCaptureService()
        let url = try makeLoudWAV(seconds: 1)

        XCTAssertThrowsError(try service.completeFinishCapture(at: url, recorderSeconds: 0.05, wallSeconds: 0.5)) { error in
            guard case AudioCaptureError.captureTooShort = error else {
                return XCTFail("expected captureTooShort, got \(error)")
            }
        }

        XCTAssertEqual(captureLines().count, 0)
        XCTAssertEqual(rejectionLines().count, 1)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFinishEmptyFileRejectionRecordsOnlyRejection() throws {
        let service = AudioCaptureService()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-empty-\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: url.path, contents: Data())

        XCTAssertThrowsError(try service.completeFinishCapture(at: url, recorderSeconds: 1.0, wallSeconds: 1.2)) { error in
            guard case AudioCaptureError.outputFileEmpty = error else {
                return XCTFail("expected outputFileEmpty, got \(error)")
            }
        }

        XCTAssertEqual(captureLines().count, 0)
        XCTAssertEqual(rejectionLines().count, 1)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnalysisRejectionConsumesWallTimeAndRecordsRejection() async throws {
        let service = AudioCaptureService()
        let url = try makeSilentWAV(seconds: 1)
        // Verdict removes rejected files; no defer removal needed.
        service.storeDiagnosticWallSecondsIfEnabled(2.0, for: url)

        do {
            _ = try await service.analyzeCaptureFile(at: url)
            XCTFail("expected audioLevelTooLow")
        } catch {
            guard case AudioCaptureError.audioLevelTooLow = error else {
                throw error
            }
        }

        XCTAssertEqual(captureLines().count, 0)
        XCTAssertEqual(rejectionLines().count, 1)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
    }

    func testAnalysisSuccessConsumesWallTimeWithoutSecondCaptureLine() async throws {
        let service = AudioCaptureService()
        let url = try makeLoudWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        // Full stage-1 → stage-2 lifecycle through production policy.
        _ = try service.completeFinishCapture(at: url, recorderSeconds: 1.0, wallSeconds: 2.0)
        let analysis = try await service.analyzeCaptureFile(at: url)

        XCTAssertFalse(analysis.isSilent)
        XCTAssertEqual(captureLines().count, 1)
        XCTAssertEqual(rejectionLines().count, 0)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnalysisDecodeSkippedConsumesWallTimeWithoutRejection() async throws {
        let service = AudioCaptureService()
        let url = try makeGarbageWAV()
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try service.completeFinishCapture(at: url, recorderSeconds: 1.0, wallSeconds: 2.0)
        let analysis = try await service.analyzeCaptureFile(at: url)

        XCTAssertEqual(analysis, AudioAnalysis.decodeSkipped)
        XCTAssertEqual(captureLines().count, 1)
        XCTAssertEqual(rejectionLines().count, 0)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: url))
    }

    func testCompatibilityStopDoesNotDuplicateCaptureOrRejectionLines() throws {
        let service = AudioCaptureService()

        // Success path: finish logs one capture, sync verify consumes without a second line.
        let loudURL = try makeLoudWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: loudURL) }
        _ = try service.completeFinishCapture(at: loudURL, recorderSeconds: 1.0, wallSeconds: 2.0)
        _ = try service.verifyCompatibilityCapture(at: loudURL)
        XCTAssertEqual(captureLines().count, 1)
        XCTAssertEqual(rejectionLines().count, 0)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: loudURL))

        // Failure path: finish logs one capture, sync verify logs one rejection and keeps the copy.
        let silentURL = try makeSilentWAV(seconds: 1)
        _ = try service.completeFinishCapture(at: silentURL, recorderSeconds: 1.0, wallSeconds: 2.0)
        XCTAssertThrowsError(try service.verifyCompatibilityCapture(at: silentURL)) { error in
            guard case AudioCaptureError.audioLevelTooLow = error else {
                return XCTFail("expected audioLevelTooLow, got \(error)")
            }
        }
        XCTAssertEqual(captureLines().count, 2)
        XCTAssertEqual(rejectionLines().count, 1)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: silentURL))

        // Decode-skipped path: consumes without rejection or duplicate capture.
        let garbageURL = try makeGarbageWAV()
        defer { try? FileManager.default.removeItem(at: garbageURL) }
        _ = try service.completeFinishCapture(at: garbageURL, recorderSeconds: 1.0, wallSeconds: 2.0)
        _ = try service.verifyCompatibilityCapture(at: garbageURL)
        XCTAssertEqual(captureLines().count, 3)
        XCTAssertEqual(rejectionLines().count, 1)
        XCTAssertNil(service.takeDiagnosticWallSeconds(for: garbageURL))
    }

    // MARK: - Helpers

    /// Lines emitted by `recordCapture` (which always includes `recorder=`; rejections do not).
    private func captureLines() -> [String] {
        readLog().filter { $0.contains("capture=") && $0.contains("recorder=") }
    }

    private func rejectionLines() -> [String] {
        readLog().filter { $0.contains("rejected=") }
    }

    private func readLog() -> [String] {
        let logURL = directory.appendingPathComponent("capture-diagnostics.log")
        guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return contents.split(separator: "\n").map(String.init)
    }

    private func makeSilentWAV(seconds: Double) throws -> URL {
        try makeWAV(seconds: seconds, amplitude: 0)
    }

    private func makeLoudWAV(seconds: Double) throws -> URL {
        try makeWAV(seconds: seconds, amplitude: 0.3)
    }

    private func makeWAV(seconds: Double, amplitude: Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-lifecycle-\(UUID().uuidString)")
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
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(frames) {
                    channels[channel][frame] = amplitude
                }
            }
        }
        try file.write(from: buffer)
        return url
    }

    private func makeGarbageWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-lifecycle-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try String(repeating: "not audio ", count: 20).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
