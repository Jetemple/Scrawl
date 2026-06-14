@testable import AppUI
import XCTest

final class LocalModelManagerCancelTests: XCTestCase {
    func testCancelIsNoOpWhenNoDownloadInProgress() {
        let manager = LocalModelManager(modelsDirectoryURL: FileManager.default.temporaryDirectory)
        XCTAssertFalse(manager.cancelDownload())
        // No active download — flags must stay false/clear after a no-op cancel.
        XCTAssertFalse(manager.isDownloadInProgress)
        XCTAssertTrue(manager.pendingResumeDataBySourceURL.isEmpty)
    }

    func testCancelledOperationNoLongerOwnsDownloadSlot() throws {
        var state = ModelDownloadOperationState()
        let operationID = try state.begin(modelID: "ggml-medium")

        XCTAssertTrue(state.cancel())

        XCTAssertFalse(state.owns(operationID))
        XCTAssertNil(state.activeOperationID)
    }

    func testOldSameModelCleanupDoesNotClearRestartedDownload() throws {
        var state = ModelDownloadOperationState()
        let oldOperationID = try state.begin(modelID: "ggml-medium")
        state.cancel()
        let newOperationID = try state.begin(modelID: "ggml-medium")

        state.finish(oldOperationID)

        XCTAssertTrue(state.owns(newOperationID))
        XCTAssertEqual(state.activeModelID, "ggml-medium")
    }

    func testSecondConcurrentDownloadIsRejected() throws {
        var state = ModelDownloadOperationState()
        _ = try state.begin(modelID: "ggml-medium")

        XCTAssertThrowsError(try state.begin(modelID: "ggml-small.en"))
    }

    func testFinishedOperationCannotBeCancelled() throws {
        var state = ModelDownloadOperationState()
        let operationID = try state.begin(modelID: "ggml-medium")
        state.finish(operationID)

        XCTAssertFalse(state.cancel())
    }
}
