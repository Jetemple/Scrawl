@testable import AppUI
import XCTest

final class LocalModelManagerCancelTests: XCTestCase {
    func testCancelIsNoOpWhenNoDownloadInProgress() {
        let manager = LocalModelManager(modelsDirectoryURL: FileManager.default.temporaryDirectory)
        manager.cancelDownload()
        // No active download — flags must stay false/clear after a no-op cancel.
        XCTAssertFalse(manager.isDownloadInProgress)
        XCTAssertTrue(manager.pendingResumeDataByModelID.isEmpty)
    }
}
