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

    func testDownloadProgressMapperUsesOverallFileCompletionAndOnlyHitsOneAtCompletion() {
        let mappedFractions = [10, 20, 23].map { completedFiles in
            let progress = DownloadUtils.DownloadProgress(
                fractionCompleted: completedFiles == 23 ? 0.5 : 0.485,
                phase: .downloading(completedFiles: completedFiles, totalFiles: 23)
            )
            return ParakeetDownloadProgressMapper.map(progress)
        }

        let mappedDownload = mappedFractions[1]

        XCTAssertEqual(mappedDownload.phase, .downloading)
        XCTAssertEqual(mappedDownload.fractionCompleted ?? -1, 20.0 / 23.0, accuracy: 0.001)
        XCTAssertLessThan(mappedDownload.fractionCompleted ?? 1, 1.0)

        XCTAssertEqual(mappedFractions.map(\.phase), [.downloading, .downloading, .downloading])
        XCTAssertEqual(mappedFractions[0].fractionCompleted ?? -1, 10.0 / 23.0, accuracy: 0.001)
        XCTAssertEqual(mappedFractions[2].fractionCompleted ?? -1, 1.0, accuracy: 0.001)
        XCTAssertLessThan(mappedFractions[0].fractionCompleted ?? 1, mappedFractions[1].fractionCompleted ?? 0)
        XCTAssertLessThan(mappedFractions[1].fractionCompleted ?? 1, mappedFractions[2].fractionCompleted ?? 0)
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
