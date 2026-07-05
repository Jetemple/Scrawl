import AppKit
@testable import AppUI
import XCTest

final class PreferencesModelsViewSnapshotTests: XCTestCase {
    @MainActor
    func testWritesModelsPageSnapshotsWhenSnapshotDirectoryIsProvided() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["SCRAWL_SNAPSHOT_DIR"], !outputPath.isEmpty else {
            throw XCTSkip("Set SCRAWL_SNAPSHOT_DIR to write Preferences Models PNG snapshots.")
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try PreferencesModelsSnapshotWriter.writeSnapshots(to: outputDirectory)

        for name in ["models-installed.png", "models-downloading.png", "models-minimum-width.png"] {
            let url = outputDirectory.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(name)")
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 1000, "\(name) should be a real PNG artifact")
        }
    }
}

private enum PreferencesModelsSnapshotWriter {
    @MainActor
    static func writeSnapshots(to outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try writeSnapshot(
            named: "models-installed.png",
            size: NSSize(width: 520, height: 340),
            rows: [
                modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
                modelRow(id: "ggml-small.en", installed: true, selected: false),
                modelRow(id: "ggml-medium", installed: false, selected: false),
                modelRow(id: "ggml-large-v3-turbo", installed: false, selected: false),
            ],
            downloadableModels: downloadableModels,
            isDownloadInProgress: false,
            to: outputDirectory
        )

        try writeSnapshot(
            named: "models-downloading.png",
            size: NSSize(width: 520, height: 340),
            rows: [
                modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: false),
                modelRow(id: "ggml-small.en", installed: true, selected: true),
                PreferencesModelRow(
                    id: "ggml-medium",
                    displayName: PreferencesModelState.displayName(forModelID: "ggml-medium"),
                    descriptionText: PreferencesModelState.description(forModelID: "ggml-medium"),
                    isInstalled: false,
                    isSelected: false,
                    isDownloading: true,
                    isCancelled: false,
                    downloadProgressText: "42% (630/1500 MB)"
                ),
                modelRow(id: "ggml-large-v3-turbo", installed: false, selected: false),
            ],
            downloadableModels: downloadableModels,
            isDownloadInProgress: true,
            to: outputDirectory
        )

        try writeSnapshot(
            named: "models-minimum-width.png",
            size: NSSize(width: 440, height: 340),
            rows: [
                modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
                modelRow(id: "ggml-small.en", installed: true, selected: false),
                PreferencesModelRow(
                    id: "ggml-medium",
                    displayName: PreferencesModelState.displayName(forModelID: "ggml-medium"),
                    descriptionText: PreferencesModelState.description(forModelID: "ggml-medium"),
                    isInstalled: false,
                    isSelected: false,
                    isDownloading: false,
                    isCancelled: true,
                    downloadProgressText: nil
                ),
                modelRow(id: "ggml-large-v3-turbo", installed: false, selected: false),
            ],
            downloadableModels: downloadableModels,
            isDownloadInProgress: false,
            to: outputDirectory
        )
    }

    @MainActor
    private static func writeSnapshot(
        named fileName: String,
        size: NSSize,
        rows: [PreferencesModelRow],
        downloadableModels: [DownloadableModel],
        isDownloadInProgress: Bool,
        to outputDirectory: URL
    ) throws {
        let rootView = NSView(frame: NSRect(origin: .zero, size: size))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let view = PreferencesModelsView(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {}
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            view.topAnchor.constraint(equalTo: rootView.topAnchor),
            view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        view.update(rows: rows, downloadableModels: downloadableModels, isDownloadInProgress: isDownloadInProgress)

        let window = NSWindow(
            contentRect: rootView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = rootView
        window.layoutIfNeeded()
        rootView.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        rootView.displayIfNeeded()

        guard let representation = rootView.bitmapImageRepForCachingDisplay(in: rootView.bounds) else {
            throw SnapshotError.couldNotCreateBitmap(fileName)
        }
        rootView.cacheDisplay(in: rootView.bounds, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotEncodePNG(fileName)
        }
        try pngData.write(to: outputDirectory.appendingPathComponent(fileName), options: .atomic)
    }

    private static let downloadableModels = [
        downloadableModel(id: "ggml-medium"),
        downloadableModel(id: "ggml-large-v3-turbo"),
    ]

    private static func downloadableModel(id: String) -> DownloadableModel {
        DownloadableModel(
            id: id,
            fileName: "\(id).bin",
            displayName: PreferencesModelState.displayName(forModelID: id),
            url: URL(string: "https://example.com/\(id).bin")!,
            sha256: String(repeating: "0", count: 64)
        )
    }

    private static func modelRow(id: String, installed: Bool, selected: Bool) -> PreferencesModelRow {
        PreferencesModelRow(
            id: id,
            displayName: PreferencesModelState.displayName(forModelID: id),
            descriptionText: PreferencesModelState.description(forModelID: id),
            isInstalled: installed,
            isSelected: selected,
            isDefault: selected,
            isDownloading: false,
            isCancelled: false,
            downloadProgressText: nil
        )
    }

    private enum SnapshotError: LocalizedError {
        case couldNotCreateBitmap(String)
        case couldNotEncodePNG(String)

        var errorDescription: String? {
            switch self {
            case let .couldNotCreateBitmap(fileName):
                "Could not create bitmap for \(fileName)."
            case let .couldNotEncodePNG(fileName):
                "Could not encode \(fileName) as PNG."
            }
        }
    }
}
