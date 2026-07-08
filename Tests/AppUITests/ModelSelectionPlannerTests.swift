@testable import AppUI
import XCTest

final class ModelSelectionPlannerTests: XCTestCase {
    func testCancelingRequiredParakeetDownloadKeepsPreviousSelectionAndSkipsPreparation() {
        let outcome = ModelSelectionPlanner.outcome(
            currentModelID: "ggml-small.en",
            requestedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: false,
            confirmation: .cancel
        )

        XCTAssertEqual(outcome, .cancelled(keptModelID: "ggml-small.en"))
    }

    func testConfirmingRequiredParakeetDownloadSelectsAndPreparesModel() {
        let outcome = ModelSelectionPlanner.outcome(
            currentModelID: "ggml-small.en",
            requestedModelID: "parakeet-v3",
            preparesOnSelection: true,
            isInstalled: false,
            confirmation: .download
        )

        XCTAssertEqual(
            outcome,
            .selected(ModelSelectionPlan(modelID: "parakeet-v3", shouldPrepareOnSelection: true))
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
}
