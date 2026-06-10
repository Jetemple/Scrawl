@testable import AppUI
import XCTest

final class PreferencesModelStateTests: XCTestCase {
    func testRowsMarkSelectedInstalledAndDownloadingModels() {
        let rows = PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: URL(string: "https://example.com/small.bin")!,
                    sha256: "dummy-sha256-for-tests"
                ),
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: URL(string: "https://example.com/medium.bin")!,
                    sha256: "dummy-sha256-for-tests"
                )
            ],
            installedModelIDs: ["ggml-small.en"],
            selectedModelID: "ggml-small.en",
            downloadingModelID: "ggml-medium"
        )

        XCTAssertEqual(rows.map(\.id), ["ggml-small.en", "ggml-medium"])
        XCTAssertEqual(rows[0].displayName, "small.en - recommended, 466 MB")
        XCTAssertTrue(rows[0].isInstalled)
        XCTAssertTrue(rows[0].isSelected)
        XCTAssertFalse(rows[0].isDownloading)
        XCTAssertFalse(rows[0].canDownload)
        XCTAssertFalse(rows[0].canSelect)

        XCTAssertFalse(rows[1].isInstalled)
        XCTAssertFalse(rows[1].isSelected)
        XCTAssertTrue(rows[1].isDownloading)
        XCTAssertEqual(rows[1].statusText, "Downloading")
        XCTAssertEqual(rows[1].actionTitle, "Downloading")
        XCTAssertFalse(rows[1].canDownload)
        XCTAssertFalse(rows[1].canSelect)
    }

    func testRowsIncludeInstalledCustomModelsAfterKnownDownloads() {
        let rows = PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: URL(string: "https://example.com/small.bin")!,
                    sha256: "dummy-sha256-for-tests"
                )
            ],
            installedModelIDs: ["ggml-custom-model", "ggml-small.en"],
            selectedModelID: "ggml-custom-model",
            downloadingModelID: nil
        )

        XCTAssertEqual(rows.map(\.id), ["ggml-small.en", "ggml-custom-model"])
        XCTAssertEqual(rows[1].displayName, "custom-model")
        XCTAssertTrue(rows[1].isInstalled)
        XCTAssertTrue(rows[1].isSelected)
        XCTAssertEqual(rows[1].statusText, "Selected")
        XCTAssertEqual(rows[1].actionTitle, "Selected")
        XCTAssertFalse(rows[1].canSelect)
        XCTAssertFalse(rows[1].canDownload)
    }

    func testRowsUseInstalledIDWhenCustomFilenameMatchesKnownModelFamily() {
        let rows = PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: URL(string: "https://example.com/small.bin")!,
                    sha256: "dummy-sha256-for-tests"
                )
            ],
            installedModelIDs: ["small"],
            selectedModelID: "small",
            downloadingModelID: nil
        )

        XCTAssertEqual(rows.map(\.id), ["small"])
        XCTAssertTrue(rows[0].isInstalled)
        XCTAssertTrue(rows[0].isSelected)
        XCTAssertFalse(rows[0].canDownload)
    }

    func testAvailableModelRowUsesDownloadActionText() {
        let row = PreferencesModelRow(
            id: "ggml-medium",
            displayName: "medium - multilingual, 1.5 GB",
            isInstalled: false,
            isSelected: false,
            isDownloading: false
        )

        XCTAssertEqual(row.statusText, "Available")
        XCTAssertEqual(row.actionTitle, "Download")
    }
}
