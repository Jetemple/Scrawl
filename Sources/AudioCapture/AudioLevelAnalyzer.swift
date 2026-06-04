import AVFoundation
import Foundation

public enum AudioLevelAnalyzer {
    public static func isLikelySilent(samples: [Int16], minimumRMS: Double) -> Bool {
        rootMeanSquare(samples: samples) < minimumRMS
    }

    public static func isLikelySilent(fileURL: URL, minimumRMS: Double) throws -> Bool {
        let file = try AVAudioFile(forReading: fileURL)
        guard file.length > 0 else {
            return true
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return false
        }

        try file.read(into: buffer)
        return rootMeanSquare(buffer: buffer) < minimumRMS
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

    private static func rootMeanSquare(buffer: AVAudioPCMBuffer) -> Double {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0
        }

        if let channels = buffer.floatChannelData {
            return rootMeanSquare(floatChannels: channels, channelCount: Int(buffer.format.channelCount), frameLength: frameLength)
        }

        if let channels = buffer.int16ChannelData {
            var samples: [Int16] = []
            samples.reserveCapacity(frameLength * Int(buffer.format.channelCount))
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<frameLength {
                    samples.append(channels[channel][frame])
                }
            }
            return rootMeanSquare(samples: samples)
        }

        return 1
    }

    private static func rootMeanSquare(
        floatChannels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameLength: Int
    ) -> Double {
        var sumOfSquares = 0.0
        var sampleCount = 0

        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                let sample = Double(floatChannels[channel][frame])
                sumOfSquares += sample * sample
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return 0
        }
        return sqrt(sumOfSquares / Double(sampleCount))
    }
}
