struct ActiveOperationGeneration {
    private(set) var current: UInt64 = 0
    private var currentStatus: UInt64 = 0

    var currentStatusToken: UInt64 {
        currentStatus
    }

    mutating func beginActiveOperation() {
        current &+= 1
    }

    mutating func applyStatus() -> UInt64 {
        currentStatus &+= 1
        return currentStatus
    }

    func shouldPresentDelayedFailure(
        for operationGeneration: UInt64,
        originatingStatusGeneration: UInt64,
        hasActiveOperation: Bool
    ) -> Bool {
        operationGeneration == current
            && originatingStatusGeneration == currentStatus
            && !hasActiveOperation
    }
}
