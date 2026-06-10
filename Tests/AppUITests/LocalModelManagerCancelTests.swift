@testable import AppUI
import XCTest

final class LocalModelManagerCancelTests: XCTestCase {
    func testCancelIsNoOpWhenNoDownloadInProgress() {
        let manager = LocalModelManager(modelsDirectoryURL: FileManager.default.temporaryDirectory)
        manager.cancelDownload()
        XCTAssertNil(manager.pendingResumeData)
        XCTAssertFalse(manager.isDownloadInProgress)
    }
}
