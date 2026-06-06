@testable import AppUI
import XCTest

final class ActiveOperationGenerationTests: XCTestCase {
    func testDelayedFailureMayPresentWhenNoNewerActiveOperationStarted() {
        let generation = ActiveOperationGeneration()
        let token = generation.current

        XCTAssertTrue(generation.shouldPresentDelayedFailure(for: token, hasActiveOperation: false))
    }

    func testDelayedFailureIsSuppressedAfterNewerActiveOperationStarts() {
        var generation = ActiveOperationGeneration()
        let token = generation.current

        generation.beginActiveOperation()

        XCTAssertFalse(generation.shouldPresentDelayedFailure(for: token, hasActiveOperation: false))
    }

    func testDelayedFailureIsSuppressedWhileAnActiveOperationIsVisible() {
        let generation = ActiveOperationGeneration()

        XCTAssertFalse(
            generation.shouldPresentDelayedFailure(
                for: generation.current,
                hasActiveOperation: true
            )
        )
    }

    func testEachActiveOperationStartInvalidatesEarlierTokens() {
        var generation = ActiveOperationGeneration()
        generation.beginActiveOperation()
        let firstOperationToken = generation.current

        generation.beginActiveOperation()

        XCTAssertFalse(
            generation.shouldPresentDelayedFailure(
                for: firstOperationToken,
                hasActiveOperation: false
            )
        )
        XCTAssertTrue(
            generation.shouldPresentDelayedFailure(
                for: generation.current,
                hasActiveOperation: false
            )
        )
    }
}
