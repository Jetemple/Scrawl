import AVFoundation
import Foundation

public struct AudioCaptureConfig: Sendable {
    public var sampleRate: Double
    public var channels: Int
    public var minimumDurationSeconds: Double
    public var silenceThresholdRMS: Double
    /// Minimum consecutive active-window duration (in seconds) required before sending audio to
    /// the transcriber. Windows are `activeWindowSeconds` wide; a window is "active" when its RMS
    /// exceeds `activeWindowRMS`. Raising this value reduces hallucinations on ambient noise at
    /// the cost of clipping very quiet or whispery speech — tune `activeWindowRMS` downward if
    /// that tradeoff is unacceptable for your use-case.
    public var minimumSustainedActiveSeconds: Double {
        get { activeDurationThreshold }
        set {
            activeDurationThreshold = newValue
            usesSustainedActiveDuration = true
        }
    }

    public var activeWindowSeconds: Double
    public var activeWindowRMS: Double
    fileprivate var usesSustainedActiveDuration: Bool
    private var activeDurationThreshold: Double

    /// Minimum total active-window duration used by configurations created with the legacy API.
    public var minimumActiveSeconds: Double {
        get { activeDurationThreshold }
        set {
            activeDurationThreshold = newValue
            usesSustainedActiveDuration = false
        }
    }

    public init(
        sampleRate: Double = 16000,
        channels: Int = 1,
        minimumDurationSeconds: Double = 0.18,
        silenceThresholdRMS: Double = 0.001,
        minimumSustainedActiveSeconds: Double = 0.15,
        activeWindowSeconds: Double = 0.03,
        activeWindowRMS: Double = 0.0075
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.minimumDurationSeconds = minimumDurationSeconds
        self.silenceThresholdRMS = silenceThresholdRMS
        self.activeWindowSeconds = activeWindowSeconds
        self.activeWindowRMS = activeWindowRMS
        usesSustainedActiveDuration = true
        activeDurationThreshold = minimumSustainedActiveSeconds
    }

    public init(
        sampleRate: Double = 16000,
        channels: Int = 1,
        minimumDurationSeconds: Double = 0.18,
        silenceThresholdRMS: Double = 0.001,
        minimumActiveSeconds: Double,
        activeWindowSeconds: Double = 0.03,
        activeWindowRMS: Double = 0.0075
    ) {
        self.init(
            sampleRate: sampleRate,
            channels: channels,
            minimumDurationSeconds: minimumDurationSeconds,
            silenceThresholdRMS: silenceThresholdRMS,
            minimumSustainedActiveSeconds: minimumActiveSeconds,
            activeWindowSeconds: activeWindowSeconds,
            activeWindowRMS: activeWindowRMS
        )
        self.minimumActiveSeconds = minimumActiveSeconds
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
            "Recording is already in progress."
        case .notCapturing:
            "No active recording to stop."
        case .recorderCreationFailed:
            "Could not create audio recorder."
        case .recorderStartFailed:
            "Could not start recording."
        case let .captureTooShort(durationSeconds):
            String(format: "Recording was too short (%.2fs).", durationSeconds)
        case .outputFileEmpty:
            "Recorded audio was empty."
        case .audioLevelTooLow:
            "No audio was captured. Check your microphone and try again."
        }
    }
}

public protocol AudioCaptureServing: Sendable {
    func startCapture() throws
    func stopCapture() throws -> URL
    /// Stops the recorder and runs the cheap rejections (duration, file size),
    /// returning the capture file without running audio analysis. Pair with
    /// `analyzeCaptureFile(at:)` to reproduce `stopCapture()` in two stages.
    func finishCapture() throws -> URL
    /// Decodes `url` and runs the silence/active-duration verdicts off the calling
    /// thread. Throws `audioLevelTooLow` exactly where `stopCapture()` would.
    /// An undecodable file passes through, matching the legacy `try?` fallbacks.
    func analyzeCaptureFile(at url: URL) async throws -> AudioAnalysis
    /// Instantaneous input level in decibels (typically -160...0) for the live
    /// recording indicator. nil when no capture is in progress.
    func currentAveragePower() -> Float?
}

public extension AudioCaptureServing {
    /// Default for conformers that only implement the combined `stopCapture()`
    /// (e.g. test stubs): finishing alone is the whole stop.
    func finishCapture() throws -> URL {
        try stopCapture()
    }

    /// Default verdict using default configuration, computed off the calling thread.
    func analyzeCaptureFile(at url: URL) async throws -> AudioAnalysis {
        try await Task.detached(priority: .userInitiated) {
            guard let samples = try? AudioLevelAnalyzer.samples(fromFileURL: url) else {
                return AudioAnalysis.decodeSkipped
            }
            let config = AudioCaptureConfig()
            let analysis = AudioLevelAnalyzer.analyze(
                samples: samples,
                sampleRate: config.sampleRate,
                silenceThresholdRMS: config.silenceThresholdRMS,
                windowSeconds: config.activeWindowSeconds,
                activeRMS: config.activeWindowRMS
            )
            if samples.isEmpty || analysis.isSilent {
                throw AudioCaptureError.audioLevelTooLow
            }
            if analysis.longestActiveSeconds < config.minimumSustainedActiveSeconds {
                throw AudioCaptureError.audioLevelTooLow
            }
            return analysis
        }.value
    }
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
            AVLinearPCMIsNonInterleaved: false,
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
        let outputURL = try finishCapture()
        if let samples = try? AudioLevelAnalyzer.samples(fromFileURL: outputURL) {
            try Self.verdict(samples: samples, config: config, removing: outputURL)
        }
        return outputURL
    }

    public func finishCapture() throws -> URL {
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

        return outputURL
    }

    public func analyzeCaptureFile(at url: URL) async throws -> AudioAnalysis {
        let config = config
        return try await Task.detached(priority: .userInitiated) {
            // A failed decode skips the checks, matching the old per-check `try?`
            // fallbacks that let the recording through.
            guard let samples = try? AudioLevelAnalyzer.samples(fromFileURL: url) else {
                return AudioAnalysis.decodeSkipped
            }
            return try Self.verdict(samples: samples, config: config, removing: url)
        }.value
    }

    /// Shared silence/active verdict behind both `stopCapture()` and
    /// `analyzeCaptureFile(at:)`. Removes a rejected file, like the legacy code.
    private static func verdict(samples: [Int16], config: AudioCaptureConfig, removing outputURL: URL) throws -> AudioAnalysis {
        // Decode once and run the fused silence/active analysis on the same samples.
        let analysis = AudioLevelAnalyzer.analyze(
            samples: samples,
            sampleRate: config.sampleRate,
            silenceThresholdRMS: config.silenceThresholdRMS,
            windowSeconds: config.activeWindowSeconds,
            activeRMS: config.activeWindowRMS
        )
        if samples.isEmpty || analysis.isSilent {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioCaptureError.audioLevelTooLow
        }

        let activeSeconds: Double = if config.usesSustainedActiveDuration {
            analysis.longestActiveSeconds
        } else {
            analysis.totalActiveSeconds
        }
        let requiredActiveSeconds = config.usesSustainedActiveDuration
            ? config.minimumSustainedActiveSeconds
            : config.minimumActiveSeconds
        if activeSeconds < requiredActiveSeconds {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioCaptureError.audioLevelTooLow
        }
        return analysis
    }

    public func currentAveragePower() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        guard let recorder else { return nil }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }
}
