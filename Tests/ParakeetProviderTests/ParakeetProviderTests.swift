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

        let realDownload = DownloadUtils.DownloadProgress(
            fractionCompleted: 0.25,
            phase: .downloading(completedFiles: 2, totalFiles: 4)
        )
        let mappedDownload = ParakeetDownloadProgressMapper.map(realDownload)

        XCTAssertEqual(mappedDownload.phase, .downloading)
        XCTAssertEqual(mappedDownload.fractionCompleted ?? -1, 0.5, accuracy: 0.001)

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
