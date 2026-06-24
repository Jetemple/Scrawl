@testable import AppUI
import XCTest

final class ModelDeletionPromptTests: XCTestCase {
    func testBuiltInModelOffersToDownloadAgainAndKeepsSize() {
        let text = ModelDeletionPrompt.informativeText(sizeNote: " (466 MB)", isBuiltIn: true)
        XCTAssertTrue(text.contains("466 MB"))
        XCTAssertTrue(text.contains("download it again"))
    }

    func testCustomModelDoesNotPromiseADownload() {
        let text = ModelDeletionPrompt.informativeText(sizeNote: "", isBuiltIn: false)
        // A user-imported model has no download source — never promise re-download.
        XCTAssertFalse(text.lowercased().contains("download"))
        XCTAssertTrue(text.contains("add the file again"))
    }
}
