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

enum LaunchModelResolution: Equatable, Sendable {
    /// Keep the persisted selection; warm/prepare it in place if it needs preparation.
    case prepareSelectedIfNeeded
    /// The persisted selection needs a full download: select an installed fallback now,
    /// prepare the original selection as pending, and cut over when it becomes ready.
    case demoteAndPrepare(fallbackModelID: String, pendingModelID: String)
}

enum ModelSelectionPlanner {
    static func requiresDownloadConfirmation(
        preparesOnSelection: Bool,
        isInstalled: Bool
    ) -> Bool {
        preparesOnSelection && !isInstalled
    }

    /// Launch-time counterpart to `outcome(...)`: the persisted selection may point at a
    /// prepares-on-selection model whose cache is gone (deleted, or migration from a build
    /// that committed the selection before download). Selecting it in place would refuse
    /// dictation until setup finishes, so demote to an installed fallback and reuse the
    /// pending-cutover path. An installed (cache-complete) model only needs a fast warm-up,
    /// so it stays selected — demoting it would flap the selection for no benefit.
    static func launchResolution(
        selectedModelID: String,
        preparesOnSelection: Bool,
        isInstalled: Bool,
        installedFallbackModelID: String?
    ) -> LaunchModelResolution {
        guard preparesOnSelection, !isInstalled, let fallback = installedFallbackModelID else {
            return .prepareSelectedIfNeeded
        }
        return .demoteAndPrepare(fallbackModelID: fallback, pendingModelID: selectedModelID)
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
