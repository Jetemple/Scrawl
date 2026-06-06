@testable import AppUI
import XCTest

final class ActiveOperationGenerationTests: XCTestCase {
    func testDelayedFailureMayPresentWhileOriginatingStatusIsStillCurrent() {
        var generation = ActiveOperationGeneration()
        let statusToken = generation.applyStatus()

        XCTAssertTrue(
            generation.shouldPresentDelayedFailure(
                for: generation.current,
                originatingStatusGeneration: statusToken,
                hasActiveOperation: false
            )
        )
    }

    func testDelayedFailureIsSuppressedAfterNewerActiveOperationStarts() {
        var generation = ActiveOperationGeneration()
        let operationToken = generation.current
        let statusToken = generation.applyStatus()

        generation.beginActiveOperation()

        XCTAssertFalse(
            generation.shouldPresentDelayedFailure(
                for: operationToken,
                originatingStatusGeneration: statusToken,
                hasActiveOperation: false
            )
        )
    }

    func testDelayedFailureIsSuppressedAfterNewerNonActiveStatus() {
        var generation = ActiveOperationGeneration()
        let operationToken = generation.current
        let originatingStatusToken = generation.applyStatus()

        _ = generation.applyStatus()

        XCTAssertFalse(
            generation.shouldPresentDelayedFailure(
                for: operationToken,
                originatingStatusGeneration: originatingStatusToken,
                hasActiveOperation: false
            )
        )
    }

    func testDelayedFailureIsSuppressedWhileAnActiveOperationIsVisible() {
        var generation = ActiveOperationGeneration()
        let statusToken = generation.applyStatus()

        XCTAssertFalse(
            generation.shouldPresentDelayedFailure(
                for: generation.current,
                originatingStatusGeneration: statusToken,
                hasActiveOperation: true
            )
        )
    }

    func testEachActiveOperationStartInvalidatesEarlierTokens() {
        var generation = ActiveOperationGeneration()
        generation.beginActiveOperation()
        let firstOperationToken = generation.current
        let firstStatusToken = generation.applyStatus()

        generation.beginActiveOperation()
        let secondStatusToken = generation.applyStatus()

        XCTAssertFalse(
            generation.shouldPresentDelayedFailure(
                for: firstOperationToken,
                originatingStatusGeneration: firstStatusToken,
                hasActiveOperation: false
            )
        )
        XCTAssertTrue(
            generation.shouldPresentDelayedFailure(
                for: generation.current,
                originatingStatusGeneration: secondStatusToken,
                hasActiveOperation: false
            )
        )
    }
}
