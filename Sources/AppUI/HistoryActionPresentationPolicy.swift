enum PasteOutcome: Equatable {
    case pasted
    case copiedForSecureInput
    case failed(String)

    var repasteStatus: String? {
        self == .pasted ? "Repasted transcript" : nil
    }
}

struct HistoryActionPresentationPolicy {
    enum Completion {
        case success
        case failure
    }

    enum Decision: Equatable {
        case presentSuccess
        case presentFailure
        case queueFailure
        case ignore
    }

    private var currentAction: UInt64 = 0
    private var hasUnresolvedFailure = false

    mutating func beginAction() -> UInt64 {
        currentAction &+= 1
        hasUnresolvedFailure = false
        return currentAction
    }

    mutating func decision(
        for action: UInt64,
        completion: Completion,
        hasActiveOperation: Bool
    ) -> Decision {
        switch completion {
        case .failure:
            hasUnresolvedFailure = true
            return hasActiveOperation ? .queueFailure : .presentFailure
        case .success:
            guard action == currentAction, !hasUnresolvedFailure, !hasActiveOperation else {
                return .ignore
            }
            return .presentSuccess
        }
    }
}
