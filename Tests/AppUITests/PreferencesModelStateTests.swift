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

    // The ggml- prefix is normalised away so an installed "small.en" file (without the
    // ggml- prefix) still satisfies the downloadable entry whose id is "ggml-small.en".
    func testRowsUseInstalledIDWhenGgmlPrefixAbsentButFamilyMatches() {
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
            installedModelIDs: ["small.en"],
            selectedModelID: "small.en",
            downloadingModelID: nil
        )

        XCTAssertEqual(rows.map(\.id), ["small.en"])
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
            isDownloading: false,
            isCancelled: false
        )

        XCTAssertEqual(row.statusText, "Available")
        XCTAssertEqual(row.actionTitle, "Download")
    }

    func testCancelledModelShowsCancelledStatusAndCanBeReDownloaded() {
        let rows = PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: URL(string: "https://example.com/medium.bin")!,
                    sha256: "dummy-sha256-for-tests"
                )
            ],
            installedModelIDs: [],
            selectedModelID: "",
            downloadingModelID: nil,
            cancelledModelID: "ggml-medium"
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isCancelled)
        XCTAssertEqual(rows[0].statusText, "Download cancelled")
        XCTAssertTrue(rows[0].canDownload)
        XCTAssertFalse(rows[0].isDownloading)
    }

    // Regression: installed ggml-medium.en must NOT suppress the downloadable ggml-medium.
    func testInstalledEnglishVariantDoesNotSatisfyMultilingualDownloadable() {
        let rows = PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: URL(string: "https://example.com/medium.bin")!,
                    sha256: "dummy-sha256-for-tests"
                )
            ],
            installedModelIDs: ["ggml-medium.en"],
            selectedModelID: "ggml-medium.en",
            downloadingModelID: nil
        )
        // ggml-medium must still appear as downloadable (not installed).
        XCTAssertEqual(rows.count, 2)
        let mediumRow = rows.first { $0.id == "ggml-medium" }
        XCTAssertNotNil(mediumRow, "ggml-medium row must be present")
        XCTAssertFalse(mediumRow!.isInstalled, "ggml-medium must not be considered installed when only ggml-medium.en is present")
        XCTAssertTrue(mediumRow!.canDownload, "ggml-medium must remain downloadable")
    }

    // Regression: installed ggml-medium must NOT satisfy the downloadable ggml-medium.en.
    func testInstalledMultilingualDoesNotSatisfyEnglishVariantDownloadable() {
        let rows = PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-medium.en",
                    fileName: "ggml-medium.en.bin",
                    displayName: "medium.en - English only, 1.5 GB",
                    url: URL(string: "https://example.com/medium.en.bin")!,
                    sha256: "dummy-sha256-for-tests"
                )
            ],
            installedModelIDs: ["ggml-medium"],
            selectedModelID: "ggml-medium",
            downloadingModelID: nil
        )
        // ggml-medium.en must still appear as downloadable (not installed).
        XCTAssertEqual(rows.count, 2)
        let mediumEnRow = rows.first { $0.id == "ggml-medium.en" }
        XCTAssertNotNil(mediumEnRow, "ggml-medium.en row must be present")
        XCTAssertFalse(mediumEnRow!.isInstalled, "ggml-medium.en must not be considered installed when only ggml-medium is present")
        XCTAssertTrue(mediumEnRow!.canDownload, "ggml-medium.en must remain downloadable")
    }
}
