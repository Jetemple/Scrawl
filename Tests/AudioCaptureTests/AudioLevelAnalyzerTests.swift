import AudioCapture
import Foundation
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
        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: 16000)
        XCTAssertEqual(active, 0.0)
    }

    func testLowRoomToneNoiseYieldsZeroActiveSeconds() {
        // Deterministic LCG pseudo-noise, amplitude ≈ 100/32767 ≈ 0.003 — below the 0.0075 threshold
        var samples = [Int16]()
        samples.reserveCapacity(16000)
        var state: UInt64 = 12345
        for _ in 0..<16000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let amplitude = Int16(Int64(bitPattern: state) % 100)
            samples.append(amplitude)
        }
        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: 16000)
        XCTAssertEqual(active, 0.0, "Room-tone-level noise should register 0 active seconds")
    }

    func testShortBurstIsDetectedButBelowSpeechDuration() {
        // 50ms burst of amplitude 0.3 embedded in 1s of silence
        let sampleRate: Double = 16000
        let totalSamples = Int(sampleRate) // 1 second
        let burstSamples = Int(sampleRate * 0.05) // 50 ms
        let burstOffset = Int(sampleRate * 0.2) // start at 200ms
        let amplitude = Int16(Int16.max / 3) // ≈ 0.333 normalized

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
        let sampleRate: Double = 1000
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
        let sampleRate: Double = 1000
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
        let sampleRate: Double = 1000
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
        let sampleRate: Double = 16000
        let amplitude = Int16(Int16.max / 10) // ≈ 0.1 normalized
        var samples = [Int16]()
        samples.reserveCapacity(Int(sampleRate))
        for i in 0..<Int(sampleRate) {
            samples.append(i % 2 == 0 ? amplitude : -amplitude)
        }

        let active = AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: sampleRate)
        XCTAssertGreaterThanOrEqual(active, 0.9, "1s of speech-like signal must yield ≥0.9s active")
    }

    func testFusedAnalysisAgreesWithLegacyEntryPoints() {
        let sampleRate: Double = 16000
        // 1s silence, 300ms speech-like burst, 200ms room tone, trailing partial window
        var samples = [Int16](repeating: 0, count: 16000)
        let amp = Int16(Int16.max / 3)
        for i in 16000..<(16000 + 4800) {
            samples.append((i % 2 == 0) ? amp : -amp)
        }
        var state: UInt64 = 999
        for _ in 0..<3200 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            samples.append(Int16(Int64(bitPattern: state) % 100))
        }
        samples.append(contentsOf: [Int16](repeating: amp, count: 17)) // partial window
        let fused = AudioLevelAnalyzer.analyze(samples: samples, sampleRate: sampleRate, silenceThresholdRMS: 0.001)
        XCTAssertEqual(fused.isSilent, AudioLevelAnalyzer.isLikelySilent(samples: samples, minimumRMS: 0.001))
        XCTAssertEqual(fused.longestActiveSeconds,
                       AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: sampleRate), accuracy: 0.0)
        XCTAssertEqual(fused.totalActiveSeconds,
                       AudioLevelAnalyzer.activeAudioSeconds(samples: samples, sampleRate: sampleRate), accuracy: 0.0)
    }

    func testFusedAnalysisEmptyInput() {
        let fused = AudioLevelAnalyzer.analyze(samples: [], sampleRate: 16000, silenceThresholdRMS: 0.001)
        XCTAssertTrue(fused.isSilent)
        XCTAssertEqual(fused.longestActiveSeconds, 0.0)
        XCTAssertEqual(fused.totalActiveSeconds, 0.0)
    }

    func testAsyncAnalysisParityWithSyncVerdicts() async throws {
        let service = AudioCaptureService()
        let url = try Self.writeWAV(samples: [Int16](repeating: Int16(Int16.max / 3), count: 4800), sampleRate: 16000)
        defer { try? FileManager.default.removeItem(at: url) }
        let analysis = try await service.analyzeCaptureFile(at: url)
        let samples = try AudioLevelAnalyzer.samples(fromFileURL: url)
        XCTAssertEqual(analysis, AudioLevelAnalyzer.analyze(
            samples: samples, sampleRate: 16000, silenceThresholdRMS: service.config.silenceThresholdRMS,
            windowSeconds: service.config.activeWindowSeconds, activeRMS: service.config.activeWindowRMS
        ))
        XCTAssertFalse(analysis.isSilent)
    }

    @MainActor
    func testAnalyzeRunsOffMainThread() async throws {
        let url = try Self.writeWAV(samples: Self.longSpeechLikeBuffer(seconds: 600), sampleRate: 16000)
        defer { try? FileManager.default.removeItem(at: url) }
        var mainWasFree = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { mainWasFree = true }
        _ = try await AudioCaptureService().analyzeCaptureFile(at: url)
        XCTAssertTrue(mainWasFree, "main thread must stay responsive during analysis")
    }

    private static func writeWAV(samples: [Int16], sampleRate: Double) throws -> URL {
        // Minimal PCM16-mono WAV writer: deterministic, no framework behavior in the
        // test helper. The read path under test stays AVAudioFile (production code).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrawl-test-\(UUID().uuidString)").appendingPathExtension("wav")
        var data = Data()
        data.reserveCapacity(44 + samples.count * 2)
        func u32(_ v: UInt32) {
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        func u16(_ v: UInt16) {
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        u32(UInt32(36 + samples.count * 2))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        u32(16)
        u16(1) // PCM
        u16(1) // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * 2) // byte rate
        u16(2) // block align
        u16(16) // bits per sample
        data.append(contentsOf: "data".utf8)
        u32(UInt32(samples.count * 2))
        samples.withUnsafeBufferPointer { src in
            data.append(contentsOf: UnsafeRawBufferPointer(src))
        }
        try data.write(to: url)
        return url
    }

    private static func longSpeechLikeBuffer(seconds: Int) -> [Int16] {
        // Alternating 1s speech-like / 1s silence at 16kHz.
        let amp = Int16(Int16.max / 3)
        var out = [Int16]()
        out.reserveCapacity(seconds * 16000)
        for s in 0..<seconds {
            if s % 2 == 0 {
                for i in 0..<16000 {
                    out.append((i % 2 == 0) ? amp : -amp)
                }
            } else {
                out.append(contentsOf: [Int16](repeating: 0, count: 16000))
            }
        }
        return out
    }

    func testFusedVersusLegacyPerformance() {
        let samples = Self.longSpeechLikeBuffer(seconds: 600)
        measure { _ = AudioLevelAnalyzer.analyze(samples: samples, sampleRate: 16000, silenceThresholdRMS: 0.001) }
    }
}
