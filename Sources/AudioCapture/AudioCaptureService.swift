import AVFoundation
import Foundation

public struct AudioCaptureConfig: Sendable {
    public var sampleRate: Double
    public var channels: Int

    public init(sampleRate: Double = 16_000, channels: Int = 1) {
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

public enum AudioCaptureError: Error {
    case alreadyCapturing
    case notCapturing
    case recorderCreationFailed
    case recorderStartFailed
}

public protocol AudioCaptureServing: Sendable {
    func startCapture() throws
    func stopCapture() throws -> URL
}

public final class AudioCaptureService: AudioCaptureServing, @unchecked Sendable {
    public let config: AudioCaptureConfig
    private let lock = NSLock()
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    public init(config: AudioCaptureConfig = AudioCaptureConfig()) {
        self.config = config
    }

    public func startCapture() throws {
        lock.lock()
        defer { lock.unlock() }

        guard recorder == nil else {
            throw AudioCaptureError.alreadyCapturing
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-audio-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: config.sampleRate,
            AVNumberOfChannelsKey: config.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let recorder = try? AVAudioRecorder(url: outputURL, settings: settings) else {
            throw AudioCaptureError.recorderCreationFailed
        }

        recorder.isMeteringEnabled = false
        guard recorder.record() else {
            throw AudioCaptureError.recorderStartFailed
        }

        self.recorder = recorder
        self.outputURL = outputURL
    }

    public func stopCapture() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        guard let recorder, let outputURL else {
            throw AudioCaptureError.notCapturing
        }

        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        return outputURL
    }
}
