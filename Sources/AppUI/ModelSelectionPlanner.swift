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

        return .selected(
            ModelSelectionPlan(modelID: requestedModelID, shouldPrepareOnSelection: false)
        )
    }
}
