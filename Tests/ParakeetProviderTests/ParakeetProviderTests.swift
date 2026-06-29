import Foundation
@testable import ParakeetProvider
import TranscriptionCore
import XCTest

final class ParakeetProviderTests: XCTestCase {
    #if arch(arm64)
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
