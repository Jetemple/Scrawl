@testable import AppUI
import TranscriptionCore
import XCTest

final class ParakeetPreparationStateTests: XCTestCase {
    func testPreparationProgressMapsCachedPlaceholderAndCompileToIndeterminatePreparing() {
        var state = ParakeetPreparationState()

        state.apply(.started)
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Setting up Parakeet (one-time)…")
        XCTAssertEqual(state.modelRowProgressText, "Preparing")

        state.apply(.progress(.init(ModelPreparationProgress(fractionCompleted: 0.5, phase: .checkingCache))))
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Loading Parakeet…")
        XCTAssertEqual(state.modelRowProgressText, "Preparing")

        state.apply(.progress(.init(ModelPreparationProgress(fractionCompleted: 0.75, phase: .optimizing))))
        XCTAssertTrue(state.isPreparing)
        XCTAssertEqual(state.statusText, "Optimizing Parakeet for your Mac… (one-time, up to 1 min)")
        XCTAssertEqual(state.modelRowProgressText, "Preparing")

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
        XCTAssertEqual(state.statusText, "Downloading Parakeet model — 50% (about 460 MB, one time)")
        XCTAssertEqual(state.modelRowProgressText, "Downloading Parakeet model — 50%")

        state.apply(.progress(.init(fractionCompleted: 0.25, phase: .downloading)))
        XCTAssertEqual(state.statusText, "Downloading Parakeet model — 50% (about 460 MB, one time)")
        XCTAssertEqual(state.modelRowProgressText, "Downloading Parakeet model — 50%")

        state.apply(.progress(.init(fractionCompleted: 1.0, phase: .downloading)))
        XCTAssertEqual(state.statusText, "Downloading Parakeet model — 100% (about 460 MB, one time)")
        XCTAssertEqual(state.modelRowProgressText, "Downloading Parakeet model — 100%")

        state.apply(.progress(.init(fractionCompleted: nil, phase: .optimizing)))
        XCTAssertEqual(state.statusText, "Optimizing Parakeet for your Mac… (one-time, up to 1 min)")
        XCTAssertEqual(state.modelRowProgressText, "Preparing")

        state.apply(.ready)
        XCTAssertFalse(state.isPreparing)
        XCTAssertTrue(state.isReady)
        XCTAssertNil(state.statusText)
        XCTAssertNil(state.modelRowProgressText)
    }

    func testLateCacheCheckAfterDownloadDoesNotMoveStatusBackToLoading() {
        var state = ParakeetPreparationState()

        state.apply(.started)
        state.apply(.progress(.init(fractionCompleted: 1.0, phase: .downloading)))
        state.apply(.progress(.init(fractionCompleted: nil, phase: .optimizing)))
        state.apply(.progress(.init(fractionCompleted: nil, phase: .checkingCache)))

        XCTAssertEqual(state.statusText, "Optimizing Parakeet for your Mac… (one-time, up to 1 min)")
        XCTAssertEqual(state.modelRowProgressText, "Preparing")
    }

    func testLateCacheCheckDuringCachedCompileDoesNotMoveStatusBackToLoading() {
        var state = ParakeetPreparationState()

        state.apply(.started)
        state.apply(.progress(.init(fractionCompleted: nil, phase: .checkingCache)))
        state.apply(.progress(.init(fractionCompleted: nil, phase: .optimizing)))
        state.apply(.progress(.init(fractionCompleted: nil, phase: .checkingCache)))

        XCTAssertEqual(state.statusText, "Optimizing Parakeet for your Mac… (one-time, up to 1 min)")
        XCTAssertEqual(state.modelRowProgressText, "Preparing")
    }

    func testEarlyDictationWhenPreparingShowsNotReadyMessage() {
        var state = ParakeetPreparationState()
        state.apply(.started)

        let decision = ParakeetDictationReadiness.evaluate(
            preparationState: state
        )

        XCTAssertEqual(
            decision,
            .notReady(message: "Parakeet is still setting up. Pick another model to use now, or wait a moment.")
        )
    }

    func testDuplicatePreparationStatusIsSuppressedOnlyWhenConsecutiveTextMatches() {
        XCTAssertTrue(
            PreparationStatusDeduper.shouldApply(
                "Setting up Parakeet (one-time)…",
                latestStatusText: "Selected model: Parakeet v3"
            )
        )
        XCTAssertFalse(
            PreparationStatusDeduper.shouldApply(
                "Setting up Parakeet (one-time)…",
                latestStatusText: "Setting up Parakeet (one-time)…"
            )
        )
        XCTAssertTrue(
            PreparationStatusDeduper.shouldApply(
                "Downloading Parakeet model — 44%",
                latestStatusText: "Downloading Parakeet model — 43%"
            )
        )
        XCTAssertTrue(
            PreparationStatusDeduper.shouldApply(
                "Downloading Medium: 10%",
                latestStatusText: "Downloading Medium: 10%"
            )
        )
    }
}
