@testable import AppUI
import XCTest

final class ModelSelectionPlannerTests: XCTestCase {
    func testCancelingRequiredParakeetDownloadKeepsPreviousSelectionAndSkipsPreparation() {
        let outcome = ModelSelectionPlanner.outcome(
            currentModelID: "ggml-small.en",
            requestedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: false,
            isPrepared: false,
            confirmation: .cancel
        )

        XCTAssertEqual(outcome, .cancelled(keptModelID: "ggml-small.en"))
    }

    func testConfirmingUnpreparedParakeetDefersSelectionUntilReady() {
        let outcome = ModelSelectionPlanner.outcome(
            currentModelID: "ggml-small.en",
            requestedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: false,
            isPrepared: false,
            confirmation: .download
        )

        XCTAssertEqual(
            outcome,
            .pendingPreparation(ModelSelectionPlan(modelID: "parakeet-v3", shouldPrepareOnSelection: true))
        )
    }

    func testPreparedParakeetSelectsImmediately() {
        let outcome = ModelSelectionPlanner.outcome(
            currentModelID: "ggml-small.en",
            requestedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: true,
            isPrepared: true,
            confirmation: .notRequired
        )

        XCTAssertEqual(
            outcome,
            .selected(ModelSelectionPlan(modelID: "parakeet-v3", shouldPrepareOnSelection: true))
        )
    }

    func testWhisperModelAlwaysSelectsImmediately() {
        let outcome = ModelSelectionPlanner.outcome(
            currentModelID: "parakeet-v3",
            requestedModelID: "ggml-medium",
            preparesOnSelection: false,
            isInstalled: true,
            isPrepared: true,
            confirmation: .notRequired
        )

        XCTAssertEqual(
            outcome,
            .selected(ModelSelectionPlan(modelID: "ggml-medium", shouldPrepareOnSelection: false))
        )
    }

    func testInstalledOrNonPreparingModelsDoNotRequireDownloadConfirmation() {
        XCTAssertFalse(
            ModelSelectionPlanner.requiresDownloadConfirmation(
                preparesOnSelection: true,
                isInstalled: true
            )
        )
        XCTAssertFalse(
            ModelSelectionPlanner.requiresDownloadConfirmation(
                preparesOnSelection: false,
                isInstalled: false
            )
        )
        XCTAssertTrue(
            ModelSelectionPlanner.requiresDownloadConfirmation(
                preparesOnSelection: true,
                isInstalled: false
            )
        )
    }

    func testLaunchResolutionKeepsWhisperSelection() {
        let resolution = ModelSelectionPlanner.launchResolution(
            selectedModelID: "ggml-small.en",
            preparesOnSelection: false,
            isInstalled: true,
            installedFallbackModelID: "ggml-tiny.en"
        )

        XCTAssertEqual(resolution, .prepareSelectedIfNeeded)
    }

    func testLaunchResolutionWarmsInstalledParakeetInPlace() {
        let resolution = ModelSelectionPlanner.launchResolution(
            selectedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: true,
            installedFallbackModelID: "ggml-tiny.en"
        )

        XCTAssertEqual(resolution, .prepareSelectedIfNeeded)
    }

    func testLaunchResolutionDemotesMissingParakeetToInstalledFallback() {
        let resolution = ModelSelectionPlanner.launchResolution(
            selectedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: false,
            installedFallbackModelID: "ggml-tiny.en"
        )

        XCTAssertEqual(
            resolution,
            .demoteAndPrepare(fallbackModelID: "ggml-tiny.en", pendingModelID: "parakeet-v3")
        )
    }

    func testLaunchResolutionWithoutFallbackPreparesInPlace() {
        let resolution = ModelSelectionPlanner.launchResolution(
            selectedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: false,
            installedFallbackModelID: nil
        )

        XCTAssertEqual(resolution, .prepareSelectedIfNeeded)
    }

    func testParakeetFailureAlertOffersRecoveryWhenParakeetIsSelected() {
        let plan = ModelSelectionPlanner.parakeetSetupFailureAlertPlan(
            selectedModelPreparesOnSelection: true
        )

        XCTAssertEqual(
            plan,
            ParakeetSetupFailureAlertPlan(
                primaryButton: "Switch to Whisper",
                secondaryButton: "Not Now",
                runsRecoveryOnPrimary: true
            )
        )
    }

    func testParakeetFailureAlertDoesNotOfferRecoveryWhenWhisperIsAlreadySelected() {
        let plan = ModelSelectionPlanner.parakeetSetupFailureAlertPlan(
            selectedModelPreparesOnSelection: false
        )

        XCTAssertEqual(
            plan,
            ParakeetSetupFailureAlertPlan(
                primaryButton: "OK",
                secondaryButton: nil,
                runsRecoveryOnPrimary: false
            )
        )
    }
}
