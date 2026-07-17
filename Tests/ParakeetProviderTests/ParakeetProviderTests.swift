import Foundation
@testable import ParakeetProvider
import TranscriptionCore
import XCTest

#if arch(arm64)
    import FluidAudio
#endif

final class ParakeetProviderTests: XCTestCase {
    #if arch(arm64)
        func testDownloadProgressMapperTreatsZeroTotalDownloadAsIndeterminatePreparing() {
            let cachedPlaceholder = DownloadUtils.DownloadProgress(
                fractionCompleted: 0.5,
                phase: .downloading(completedFiles: 0, totalFiles: 0)
            )
            let mappedPlaceholder = ParakeetDownloadProgressMapper.map(cachedPlaceholder)

            XCTAssertEqual(mappedPlaceholder, ModelPreparationProgress(fractionCompleted: nil, phase: .checkingCache))
        }

        func testDownloadProgressMapperUsesFluidByteFractionNotFileCount() {
            let progress = DownloadUtils.DownloadProgress(
                fractionCompleted: 0.485, // FluidAudio byte fraction; download half tops out at 0.5
                phase: .downloading(completedFiles: 1, totalFiles: 23)
            )

            let mapped = ParakeetDownloadProgressMapper.map(progress)

            XCTAssertEqual(mapped.phase, .downloading)
            // 0.485 * 2 ≈ 0.97 — byte-driven, NOT the 1/23 the file count would give.
            XCTAssertEqual(mapped.fractionCompleted ?? -1, 0.97, accuracy: 0.001)
        }

        func testDownloadProgressMapperClampsByteFractionAtDownloadCompletion() {
            let progress = DownloadUtils.DownloadProgress(
                fractionCompleted: 0.75,
                phase: .downloading(completedFiles: 23, totalFiles: 23)
            )

            let mapped = ParakeetDownloadProgressMapper.map(progress)

            XCTAssertEqual(mapped.fractionCompleted ?? -1, 1.0, accuracy: 0.001) // 0.75*2 clamped to 1.0
        }

        func testDownloadProgressMapperTreatsCompileAsOptimizing() {
            let compile = DownloadUtils.DownloadProgress(
                fractionCompleted: 0.75,
                phase: .compiling(modelName: "Encoder.mlmodelc")
            )
            let mappedCompile = ParakeetDownloadProgressMapper.map(compile)

            XCTAssertEqual(mappedCompile, ModelPreparationProgress(fractionCompleted: nil, phase: .optimizing))
        }

        func testTranscribesFixtureWithNonEmptyText() async throws {
            let audioURL = try XCTUnwrap(Bundle.module.url(forResource: "clip5", withExtension: "wav"))
            let provider = ParakeetTranscriptionProvider()

            let result = try await provider.transcribe(
                TranscriptionRequest(
                    audioFileURL: audioURL,
                    modelID: TranscriptionModelID.parakeetV3,
                    language: "en",
                    promptContext: "ignored by Parakeet"
                )
            )

            XCTAssertFalse(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThan(result.latencyMS, 0)
        }
    #endif
}
