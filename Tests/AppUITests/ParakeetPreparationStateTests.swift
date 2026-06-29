@testable import AppUI
import TranscriptionCore
import XCTest

final class ParakeetPreparationStateTests: XCTestCase {
    func testLaunchPreloadRunsOnlyForSelectedParakeetWhenAvailable() {
        XCTAssertTrue(ParakeetPreloadPolicy.shouldPreload(selectedModelID: TranscriptionModelID.parakeetV3, isParakeetAvailable: true))
        XCTAssertFalse(ParakeetPreloadPolicy.shouldPreload(selectedModelID: "ggml-small.en", isParakeetAvailable: true))
        XCTAssertFalse(ParakeetPreloadPolicy.shouldPreload(selectedModelID: TranscriptionModelID.parakeetV3, isParakeetAvailable: false))
    }

    func testPreparingStateRendersDeterminateDownloadProgressThenReady() {
        var state = ParakeetPreparationState()

        state.apply(.started)
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Preparing Parakeet...")
        XCTAssertEqual(state.modelRowProgressText, "Setting up")

        state.apply(.progress(.init(fractionCompleted: 0.37, phase: .downloading)))
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Preparing Parakeet: Downloading model 37%")
        XCTAssertEqual(state.modelRowProgressText, "Downloading model 37%")

        state.apply(.progress(.init(fractionCompleted: 1.0, phase: .optimizing)))
        XCTAssertEqual(state.statusText, "Preparing Parakeet: Optimizing for your Mac")
        XCTAssertEqual(state.modelRowProgressText, "Optimizing for your Mac")

        state.apply(.ready)
        XCTAssertFalse(state.isPreparing)
        XCTAssertTrue(state.isReady)
        XCTAssertNil(state.statusText)
        XCTAssertNil(state.modelRowProgressText)
    }

    func testEarlyDictationWhenPreparingShowsNotReadyMessage() {
        var state = ParakeetPreparationState()
        state.apply(.started)

        let decision = ParakeetDictationReadiness.evaluate(
            selectedModelID: TranscriptionModelID.parakeetV3,
            isParakeetAvailable: true,
            preparationState: state
        )

        XCTAssertEqual(decision, .notReady(message: "Parakeet is still setting up — ready shortly"))
    }
}
