import AudioCapture
import XCTest

final class AudioLevelAnalyzerTests: XCTestCase {
    func testSilentSamplesAreBelowThreshold() {
        XCTAssertTrue(AudioLevelAnalyzer.isLikelySilent(samples: [0, 0, 0, 0], minimumRMS: 0.001))
    }

    func testAudibleSamplesAreAboveThreshold() {
        XCTAssertFalse(AudioLevelAnalyzer.isLikelySilent(samples: [0, 800, -800, 0], minimumRMS: 0.001))
    }

    // MARK: - longestActiveAudioSeconds(samples:sampleRate:windowSeconds:activeRMS:)

    func testAllZeroSamplesYieldZeroActiveSeconds() {
        let samples = [Int16](repeating: 0, count: 16000)
        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: 16_000)
        XCTAssertEqual(active, 0.0)
    }

    func testLowRoomToneNoiseYieldsZeroActiveSeconds() {
        // Deterministic LCG pseudo-noise, amplitude ≈ 100/32767 ≈ 0.003 — below the 0.0075 threshold
        var samples = [Int16]()
        samples.reserveCapacity(16000)
        var state: UInt64 = 12345
        for _ in 0..<16000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let amplitude = Int16(Int64(bitPattern: state) % 100)
            samples.append(amplitude)
        }
        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: 16_000)
        XCTAssertEqual(active, 0.0, "Room-tone-level noise should register 0 active seconds")
    }

    func testShortBurstIsDetectedButBelowSpeechDuration() {
        // 50ms burst of amplitude 0.3 embedded in 1s of silence
        let sampleRate: Double = 16_000
        let totalSamples = Int(sampleRate)           // 1 second
        let burstSamples = Int(sampleRate * 0.05)    // 50 ms
        let burstOffset = Int(sampleRate * 0.2)      // start at 200ms
        let amplitude = Int16(Int16.max / 3)         // ≈ 0.333 normalized

        var samples = [Int16](repeating: 0, count: totalSamples)
        for i in burstOffset..<(burstOffset + burstSamples) {
            samples[i] = (i % 2 == 0) ? amplitude : -amplitude
        }

        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: sampleRate)
        // 50ms burst should produce roughly 0.03–0.06s of active windows (one or two 30ms windows)
        XCTAssertGreaterThan(active, 0.0, "A 50ms burst above threshold must register some active time")
        XCTAssertLessThan(active, 0.15, "A 50ms burst must fall below the speech minimum of 0.15s")
    }

    func testSeparatedActiveWindowsDoNotCountAsSustainedSpeech() {
        let sampleRate: Double = 1_000
        let windowSamples = 30
        let amplitude = Int16(Int16.max / 3)
        var samples = [Int16]()

        for _ in 0..<5 {
            samples.append(contentsOf: [Int16](repeating: amplitude, count: windowSamples))
            samples.append(contentsOf: [Int16](repeating: 0, count: windowSamples))
        }

        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(
            samples: samples,
            sampleRate: sampleRate,
            windowSeconds: 0.03
        )

        XCTAssertEqual(active, 0.03, accuracy: 0.000_001)
        XCTAssertLessThan(active, 0.15, "Separated bursts must not satisfy the sustained-speech minimum")
    }

    func testActiveAudioSecondsRetainsTotalDurationSemantics() {
        let sampleRate: Double = 1_000
        let windowSamples = 30
        let amplitude = Int16(Int16.max / 3)
        var samples = [Int16]()

        for _ in 0..<5 {
            samples.append(contentsOf: [Int16](repeating: amplitude, count: windowSamples))
            samples.append(contentsOf: [Int16](repeating: 0, count: windowSamples))
        }

        let active = AudioLevelAnalyzer.activeAudioSeconds(
            samples: samples,
            sampleRate: sampleRate,
            windowSeconds: 0.03
        )

        XCTAssertEqual(active, 0.15, accuracy: 0.000_001)
    }

    func testConsecutiveActiveWindowsCountAsSustainedSpeech() {
        let sampleRate: Double = 1_000
        let amplitude = Int16(Int16.max / 3)
        let samples = [Int16](repeating: amplitude, count: 150)

        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(
            samples: samples,
            sampleRate: sampleRate,
            windowSeconds: 0.03
        )

        XCTAssertEqual(active, 0.15, accuracy: 0.000_001)
    }

    func testOneSpeechLikeSineYieldsNearlyFullActiveSeconds() {
        // 1s of sine-like alternating samples at amplitude 0.1 — clearly above threshold
        let sampleRate: Double = 16_000
        let amplitude = Int16(Int16.max / 10)  // ≈ 0.1 normalized
        var samples = [Int16]()
        samples.reserveCapacity(Int(sampleRate))
        for i in 0..<Int(sampleRate) {
            samples.append(i % 2 == 0 ? amplitude : -amplitude)
        }

        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: sampleRate)
        XCTAssertGreaterThanOrEqual(active, 0.9, "1s of speech-like signal must yield ≥0.9s active")
    }
}
