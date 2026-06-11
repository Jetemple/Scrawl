import AVFoundation
import Foundation

public enum AudioLevelAnalyzer {
    public static func isLikelySilent(samples: [Int16], minimumRMS: Double) -> Bool {
        rootMeanSquare(samples: samples) < minimumRMS
    }

    public static func isLikelySilent(fileURL: URL, minimumRMS: Double) throws -> Bool {
        let samples = try readInt16Samples(fileURL: fileURL)
        guard !samples.isEmpty else { return true }
        return rootMeanSquare(samples: samples) < minimumRMS
    }

    /// Returns the total number of seconds during which audio energy exceeds `activeRMS`.
    /// The signal is divided into non-overlapping windows of `windowSeconds`; each window whose
    /// RMS exceeds `activeRMS` contributes its duration to the total.
    public static func activeAudioSeconds(
        samples: [Int16],
        sampleRate: Double,
        windowSeconds: Double = 0.03,
        activeRMS: Double = 0.0075
    ) -> Double {
        guard !samples.isEmpty, sampleRate > 0, windowSeconds > 0 else { return 0 }

        let windowSize = max(1, Int(sampleRate * windowSeconds))
        var activeSeconds = 0.0
        var offset = 0

        while offset < samples.count {
            let end = min(offset + windowSize, samples.count)
            let window = Array(samples[offset..<end])
            if rootMeanSquare(samples: window) >= activeRMS {
                activeSeconds += Double(window.count) / sampleRate
            }
            offset += windowSize
        }

        return activeSeconds
    }

    /// File-based variant of `activeAudioSeconds`. Reads the file once and delegates to the
    /// sample-array implementation, sharing the same extraction helper used by `isLikelySilent(fileURL:)`.
    public static func activeAudioSeconds(
        fileURL: URL,
        sampleRate: Double,
        windowSeconds: Double = 0.03,
        activeRMS: Double = 0.0075
    ) throws -> Double {
        let samples = try readInt16Samples(fileURL: fileURL)
        return activeAudioSeconds(
            samples: samples,
            sampleRate: sampleRate,
            windowSeconds: windowSeconds,
            activeRMS: activeRMS
        )
    }

    // MARK: - Private helpers

    /// Reads an AVAudioFile and returns all samples as normalised Int16 values across all channels.
    private static func readInt16Samples(fileURL: URL) throws -> [Int16] {
        let file = try AVAudioFile(forReading: fileURL)
        guard file.length > 0 else { return [] }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return []
        }

        try file.read(into: buffer)
        return int16Samples(from: buffer)
    }

    /// Converts an AVAudioPCMBuffer to a flat [Int16] array across all channels.
    private static func int16Samples(from buffer: AVAudioPCMBuffer) -> [Int16] {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }

        if let channels = buffer.int16ChannelData {
            var samples: [Int16] = []
            samples.reserveCapacity(frameLength * Int(buffer.format.channelCount))
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<frameLength {
                    samples.append(channels[channel][frame])
                }
            }
            return samples
        }

        if let channels = buffer.floatChannelData {
            var samples: [Int16] = []
            samples.reserveCapacity(frameLength * Int(buffer.format.channelCount))
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<frameLength {
                    let clamped = max(-1.0, min(1.0, channels[channel][frame]))
                    samples.append(Int16(clamped * Float(Int16.max)))
                }
            }
            return samples
        }

        return []
    }

    private static func rootMeanSquare(samples: [Int16]) -> Double {
        guard !samples.isEmpty else {
            return 0
        }

        let sumOfSquares = samples.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / Double(Int16.max)
            return partial + normalized * normalized
        }
        return sqrt(sumOfSquares / Double(samples.count))
    }

}

