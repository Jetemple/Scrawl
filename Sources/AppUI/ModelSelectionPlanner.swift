struct ModelSelectionPlan: Equatable, Sendable {
    let modelID: String
    let shouldPrepareOnSelection: Bool
}

enum ModelSelectionConfirmation: Equatable, Sendable {
    case notRequired
    case download
    case cancel
}

enum ModelSelectionOutcome: Equatable, Sendable {
    case selected(ModelSelectionPlan)
    case pendingPreparation(ModelSelectionPlan)
    case cancelled(keptModelID: String)
}

enum ModelSelectionPlanner {
    static func requiresDownloadConfirmation(
        preparesOnSelection: Bool,
        isInstalled: Bool
    ) -> Bool {
        preparesOnSelection && !isInstalled
    }

    static func outcome(
        currentModelID: String,
        requestedModelID: String,
        preparesOnSelection: Bool,
        isInstalled: Bool,
        isPrepared: Bool,
        confirmation: ModelSelectionConfirmation
    ) -> ModelSelectionOutcome {
        if requiresDownloadConfirmation(preparesOnSelection: preparesOnSelection, isInstalled: isInstalled),
           confirmation == .cancel
        {
            return .cancelled(keptModelID: currentModelID)
        }

        if preparesOnSelection, !isPrepared {
            return .pendingPreparation(
                ModelSelectionPlan(modelID: requestedModelID, shouldPrepareOnSelection: true)
            )
        }

        // A `.selected` outcome means the model is ready to use now. Carry `preparesOnSelection`
        // (not a hardcoded false) so `completeModelSelection` warms up a just-selected Parakeet
        // whose cache is complete but whose session is cold — and, crucially, does NOT run its
        // `else { cancelParakeetPreparation() }` branch, which would tear down the ready state
        // when re-selecting an already-warm Parakeet. Whisper models pass `false` and still
        // cancel any in-flight Parakeet prep, as before.
        return .selected(
            ModelSelectionPlan(modelID: requestedModelID, shouldPrepareOnSelection: preparesOnSelection)
        )
    }
}
