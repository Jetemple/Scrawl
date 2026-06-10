@testable import AppUI
import XCTest

final class HistoryActionPresentationPolicyTests: XCTestCase {
    func testPasteOutcomeOnlyReportsRepasteSuccessForActualPaste() {
        XCTAssertEqual(PasteOutcome.pasted.repasteStatus, "Repasted transcript")
        XCTAssertNil(PasteOutcome.copiedForSecureInput.repasteStatus)
        XCTAssertNil(PasteOutcome.failed("denied").repasteStatus)
    }

    func testNewerActionSuppressesStaleSuccessButNotEarlierFailure() {
        var policy = HistoryActionPresentationPolicy()
        let earlier = policy.beginAction()
        _ = policy.beginAction()

        XCTAssertEqual(
            policy.decision(for: earlier, completion: .success, hasActiveOperation: false),
            .ignore
        )
        XCTAssertEqual(
            policy.decision(for: earlier, completion: .failure, hasActiveOperation: false),
            .presentFailure
        )
    }

    func testFailureQueuesDuringActiveOperationAndPresentsAfterward() {
        var policy = HistoryActionPresentationPolicy()
        let action = policy.beginAction()

        XCTAssertEqual(
            policy.decision(for: action, completion: .failure, hasActiveOperation: true),
            .queueFailure
        )
        XCTAssertEqual(
            policy.decision(for: action, completion: .failure, hasActiveOperation: false),
            .presentFailure
        )
    }

    func testLaterSuccessDoesNotOverwriteEarlierFailure() {
        var policy = HistoryActionPresentationPolicy()
        let earlier = policy.beginAction()
        let later = policy.beginAction()

        XCTAssertEqual(
            policy.decision(for: earlier, completion: .failure, hasActiveOperation: false),
            .presentFailure
        )
        XCTAssertEqual(
            policy.decision(for: later, completion: .success, hasActiveOperation: false),
            .ignore
        )
    }

    func testActionStartedAfterFailureCanReportRecoverySuccess() {
        var policy = HistoryActionPresentationPolicy()
        let failed = policy.beginAction()
        _ = policy.decision(for: failed, completion: .failure, hasActiveOperation: false)

        let recovery = policy.beginAction()

        XCTAssertEqual(
            policy.decision(for: recovery, completion: .success, hasActiveOperation: false),
            .presentSuccess
        )
    }

    func testSuccessDoesNotOverwriteActiveOperationStatus() {
        var policy = HistoryActionPresentationPolicy()
        let action = policy.beginAction()

        XCTAssertEqual(
            policy.decision(for: action, completion: .success, hasActiveOperation: true),
            .ignore
        )
    }
}
