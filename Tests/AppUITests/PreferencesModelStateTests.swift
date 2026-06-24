@testable import AppUI
import XCTest

final class PreferencesModelStateTests: XCTestCase {
    func testRowsMarkSelectedInstalledAndDownloadingModels() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: XCTUnwrap(URL(string: "https://example.com/small.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: XCTUnwrap(URL(string: "https://example.com/medium.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
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

    func testRowsIncludeInstalledCustomModelsAfterKnownDownloads() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: XCTUnwrap(URL(string: "https://example.com/small.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
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

    /// The ggml- prefix is normalised away so an installed "small.en" file (without the
    /// ggml- prefix) still satisfies the downloadable entry whose id is "ggml-small.en".
    func testRowsUseInstalledIDWhenGgmlPrefixAbsentButFamilyMatches() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: XCTUnwrap(URL(string: "https://example.com/small.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
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
            isCancelled: false,
            downloadProgressText: nil
        )

        XCTAssertEqual(row.statusText, "Available")
        XCTAssertEqual(row.actionTitle, "Download")
    }

    func testCancelledModelShowsCancelledStatusAndCanBeReDownloaded() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: XCTUnwrap(URL(string: "https://example.com/medium.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
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

    // Regression: a cancel that lands as the download finishes can leave the model both
    // installed AND flagged by cancelledModelID. An installed model is installed — it must
    // never render as "Download cancelled" (which produced a "Use" button next to a
    // "Download cancelled" status in the row).
    func testInstalledModelIsNeverMarkedCancelledEvenWhenCancelledIDMatches() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: XCTUnwrap(URL(string: "https://example.com/medium.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
            ],
            installedModelIDs: ["ggml-medium"],
            selectedModelID: "",
            downloadingModelID: nil,
            cancelledModelID: "ggml-medium"
        )
        let row = try XCTUnwrap(rows.first { $0.id == "ggml-medium" })
        XCTAssertTrue(row.isInstalled)
        XCTAssertFalse(row.isCancelled, "An installed model must not also be flagged cancelled")
        XCTAssertEqual(row.statusText, "Installed")
        XCTAssertEqual(row.actionTitle, "Use")
    }

    /// Defense in depth: even if a row is constructed as both installed and cancelled,
    /// statusText must prefer the installed/selected truth over the stale cancelled flag.
    func testStatusTextPrefersInstalledAndSelectedOverCancelled() {
        let installed = PreferencesModelRow(
            id: "ggml-medium", displayName: "medium",
            isInstalled: true, isSelected: false, isDownloading: false,
            isCancelled: true, downloadProgressText: nil
        )
        XCTAssertEqual(installed.statusText, "Installed")

        let selected = PreferencesModelRow(
            id: "ggml-medium", displayName: "medium",
            isInstalled: true, isSelected: true, isDownloading: false,
            isCancelled: true, downloadProgressText: nil
        )
        XCTAssertEqual(selected.statusText, "Selected")
    }

    // Regression: installed ggml-medium.en must NOT suppress the downloadable ggml-medium.
    func testInstalledEnglishVariantDoesNotSatisfyMultilingualDownloadable() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: XCTUnwrap(URL(string: "https://example.com/medium.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
            ],
            installedModelIDs: ["ggml-medium.en"],
            selectedModelID: "ggml-medium.en",
            downloadingModelID: nil
        )
        // ggml-medium must still appear as downloadable (not installed).
        XCTAssertEqual(rows.count, 2)
        let mediumRow = rows.first { $0.id == "ggml-medium" }
        XCTAssertNotNil(mediumRow, "ggml-medium row must be present")
        XCTAssertFalse(try XCTUnwrap(mediumRow?.isInstalled), "ggml-medium must not be considered installed when only ggml-medium.en is present")
        XCTAssertTrue(try XCTUnwrap(mediumRow?.canDownload), "ggml-medium must remain downloadable")
    }

    func testDownloadProgressTextAppearsOnlyOnDownloadingRow() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: XCTUnwrap(URL(string: "https://example.com/small.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
                DownloadableModel(
                    id: "ggml-medium",
                    fileName: "ggml-medium.bin",
                    displayName: "medium - multilingual, 1.5 GB",
                    url: XCTUnwrap(URL(string: "https://example.com/medium.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
            ],
            installedModelIDs: ["ggml-small.en"],
            selectedModelID: "ggml-small.en",
            downloadingModelID: "ggml-medium",
            downloadProgressText: "38% (576/1500 MB)"
        )

        // The installed row should have no progress text.
        XCTAssertNil(rows[0].downloadProgressText)
        // The downloading row should carry the progress string.
        XCTAssertEqual(rows[1].downloadProgressText, "38% (576/1500 MB)")
    }

    func testDownloadProgressTextIsNilWhenNoDownloadIsActive() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-small.en",
                    fileName: "ggml-small.en.bin",
                    displayName: "small.en - recommended, 466 MB",
                    url: XCTUnwrap(URL(string: "https://example.com/small.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
            ],
            installedModelIDs: ["ggml-small.en"],
            selectedModelID: "ggml-small.en",
            downloadingModelID: nil,
            downloadProgressText: "38% (576/1500 MB)"
        )
        // No model is downloading, so the progress text should not appear on any row.
        XCTAssertNil(rows[0].downloadProgressText)
    }

    // Regression: installed ggml-medium must NOT satisfy the downloadable ggml-medium.en.
    func testInstalledMultilingualDoesNotSatisfyEnglishVariantDownloadable() throws {
        let rows = try PreferencesModelState.rows(
            downloadableModels: [
                DownloadableModel(
                    id: "ggml-medium.en",
                    fileName: "ggml-medium.en.bin",
                    displayName: "medium.en - English only, 1.5 GB",
                    url: XCTUnwrap(URL(string: "https://example.com/medium.en.bin")),
                    sha256: "dummy-sha256-for-tests"
                ),
            ],
            installedModelIDs: ["ggml-medium"],
            selectedModelID: "ggml-medium",
            downloadingModelID: nil
        )
        // ggml-medium.en must still appear as downloadable (not installed).
        XCTAssertEqual(rows.count, 2)
        let mediumEnRow = rows.first { $0.id == "ggml-medium.en" }
        XCTAssertNotNil(mediumEnRow, "ggml-medium.en row must be present")
        XCTAssertFalse(try XCTUnwrap(mediumEnRow?.isInstalled), "ggml-medium.en must not be considered installed when only ggml-medium is present")
        XCTAssertTrue(try XCTUnwrap(mediumEnRow?.canDownload), "ggml-medium.en must remain downloadable")
    }
}
