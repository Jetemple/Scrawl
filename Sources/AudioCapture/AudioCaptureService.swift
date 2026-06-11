import AVFoundation
import Foundation

public struct AudioCaptureConfig: Sendable {
    public var sampleRate: Double
    public var channels: Int
    public var minimumDurationSeconds: Double
    public var silenceThresholdRMS: Double
    /// Minimum total active-window duration (in seconds) required before sending audio to the
    /// transcriber. Windows are `activeWindowSeconds` wide; a window is "active" when its RMS
    /// exceeds `activeWindowRMS`. Raising this value reduces hallucinations on ambient noise at
    /// the cost of clipping very quiet or whispery speech — tune `activeWindowRMS` downward if
    /// that tradeoff is unacceptable for your use-case.
    public var minimumActiveSeconds: Double
    public var activeWindowSeconds: Double
    public var activeWindowRMS: Double

    public init(
        sampleRate: Double = 16_000,
        channels: Int = 1,
        minimumDurationSeconds: Double = 0.18,
        silenceThresholdRMS: Double = 0.001,
        minimumActiveSeconds: Double = 0.15,
        activeWindowSeconds: Double = 0.03,
        activeWindowRMS: Double = 0.0075
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.minimumDurationSeconds = minimumDurationSeconds
        self.silenceThresholdRMS = silenceThresholdRMS
        self.minimumActiveSeconds = minimumActiveSeconds
        self.activeWindowSeconds = activeWindowSeconds
        self.activeWindowRMS = activeWindowRMS
    }
}

public enum AudioCaptureError: Error {
    case alreadyCapturing
    case notCapturing
    case recorderCreationFailed
    case recorderStartFailed
    case captureTooShort(durationSeconds: Double)
    case outputFileEmpty
    case audioLevelTooLow
}

extension AudioCaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "Recording is already in progress."
        case .notCapturing:
            return "No active recording to stop."
        case .recorderCreationFailed:
            return "Could not create audio recorder."
        case .recorderStartFailed:
            return "Could not start recording."
        case let .captureTooShort(durationSeconds):
            return String(format: "Recording was too short (%.2fs).", durationSeconds)
        case .outputFileEmpty:
            return "Recorded audio was empty."
        case .audioLevelTooLow:
            return "No audio was captured. Check your microphone and try again."
        }
    }
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

        recorder.isMeteringEnabled = true
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

        let durationSeconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil

        if durationSeconds < config.minimumDurationSeconds {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioCaptureError.captureTooShort(durationSeconds: durationSeconds)
        }

        let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize <= 44 {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioCaptureError.outputFileEmpty
        }

        if (try? AudioLevelAnalyzer.isLikelySilent(
            fileURL: outputURL,
            minimumRMS: config.silenceThresholdRMS
        )) == true {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioCaptureError.audioLevelTooLow
        }

        let activeSeconds = (try? AudioLevelAnalyzer.activeAudioSeconds(
            fileURL: outputURL,
            sampleRate: config.sampleRate,
            windowSeconds: config.activeWindowSeconds,
            activeRMS: config.activeWindowRMS
        )) ?? config.minimumActiveSeconds
        if activeSeconds < config.minimumActiveSeconds {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioCaptureError.audioLevelTooLow
        }

        return outputURL
    }
}
