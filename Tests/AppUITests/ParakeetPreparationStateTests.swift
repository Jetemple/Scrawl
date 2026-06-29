@testable import AppUI
import TranscriptionCore
import XCTest

final class ParakeetPreparationStateTests: XCTestCase {
    func testLaunchPreloadRunsOnlyForSelectedParakeetWhenAvailable() {
        XCTAssertTrue(ParakeetPreloadPolicy.shouldPreload(selectedModelID: TranscriptionModelID.parakeetV3, isParakeetAvailable: true))
        XCTAssertFalse(ParakeetPreloadPolicy.shouldPreload(selectedModelID: "ggml-small.en", isParakeetAvailable: true))
        XCTAssertFalse(ParakeetPreloadPolicy.shouldPreload(selectedModelID: TranscriptionModelID.parakeetV3, isParakeetAvailable: false))
    }

    func testPreparationProgressMapsCachedPlaceholderAndCompileToIndeterminatePreparing() {
        var state = ParakeetPreparationState()

        state.apply(.started)
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Preparing Parakeet...")
        XCTAssertEqual(state.modelRowProgressText, "Setting up")

        state.apply(.progress(.init(ModelPreparationProgress(fractionCompleted: 0.5, phase: .checkingCache))))
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Preparing Parakeet...")
        XCTAssertEqual(state.modelRowProgressText, "Setting up")

        state.apply(.progress(.init(ModelPreparationProgress(fractionCompleted: 0.75, phase: .optimizing))))
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Preparing Parakeet...")
        XCTAssertEqual(state.modelRowProgressText, "Setting up")

        state.apply(.ready)
        XCTAssertFalse(state.isPreparing)
        XCTAssertTrue(state.isReady)
        XCTAssertNil(state.statusText)
        XCTAssertNil(state.modelRowProgressText)
    }

    func testPreparingStateRendersRealDownloadProgressMonotonicallyThenReady() {
        var state = ParakeetPreparationState()

        state.apply(.started)
        state.apply(.progress(.init(fractionCompleted: 0.50, phase: .downloading)))
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Preparing Parakeet: Downloading Parakeet model 50%")
        XCTAssertEqual(state.modelRowProgressText, "Downloading Parakeet model 50%")

        state.apply(.progress(.init(fractionCompleted: 0.25, phase: .downloading)))
        XCTAssertEqual(state.statusText, "Preparing Parakeet: Downloading Parakeet model 50%")
        XCTAssertEqual(state.modelRowProgressText, "Downloading Parakeet model 50%")

        state.apply(.progress(.init(fractionCompleted: 1.0, phase: .downloading)))
        XCTAssertEqual(state.statusText, "Preparing Parakeet: Downloading Parakeet model 100%")
        XCTAssertEqual(state.modelRowProgressText, "Downloading Parakeet model 100%")

        state.apply(.progress(.init(fractionCompleted: nil, phase: .optimizing)))
        XCTAssertEqual(state.statusText, "Preparing Parakeet...")
        XCTAssertEqual(state.modelRowProgressText, "Setting up")

        state.apply(.ready)
        XCTAssertFalse(state.isPreparing)
        XCTAssertTrue(state.isReady)
        XCTAssertNil(state.statusText)
        XCTAssertNil(state.modelRowProgressText)
    }

    func testSelectingWhisperDuringParakeetPreparationKeepsSelectionAndDoesNotCancelPreparation() {
        let effect = ParakeetSelectionPolicy.effectForUserSelection(
            modelID: "ggml-large-v3-turbo",
            isParakeetAvailable: true
        )

        XCTAssertEqual(effect.selectedModelID, "ggml-large-v3-turbo")
        XCTAssertFalse(effect.shouldStartParakeetPreparation)
        XCTAssertFalse(effect.shouldCancelParakeetPreparation)
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
