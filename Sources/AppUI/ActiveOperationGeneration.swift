struct ActiveOperationGeneration {
    private(set) var current: UInt64 = 0

    mutating func beginActiveOperation() {
        current &+= 1
    }

    func shouldPresentDelayedFailure(
        for operationGeneration: UInt64,
        hasActiveOperation: Bool
    ) -> Bool {
        operationGeneration == current && !hasActiveOperation
    }
}
