import AppKit
@testable import AppUI
import DictionaryStore
import Permissions
import SettingsStore
import TranscriptHistoryStore
import XCTest

final class PreferencesWindowSnapshotTests: XCTestCase {
    @MainActor
    func testWritesPreferencesSnapshotsWhenSnapshotDirectoryIsProvided() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["SCRAWL_PREFERENCES_SNAPSHOT_DIR"], !outputPath.isEmpty else {
            throw XCTSkip("Set SCRAWL_PREFERENCES_SNAPSHOT_DIR to write Preferences window PNG snapshots.")
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try PreferencesWindowSnapshotWriter.writeSnapshots(to: outputDirectory)

        for name in [
            "preferences-general.png",
            "preferences-models.png",
            "preferences-history.png",
            "preferences-dictionary.png",
            "preferences-minimum-width.png",
        ] {
            let url = outputDirectory.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(name)")
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 1_000, "\(name) should be a real PNG artifact")
        }
    }
}

private enum PreferencesWindowSnapshotWriter {
    @MainActor
    static func writeSnapshots(to outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let snapshot = makeSnapshot()
        try writeSnapshot(named: "preferences-general.png", section: .general, snapshot: snapshot, to: outputDirectory)
        try writeSnapshot(named: "preferences-models.png", section: .models, snapshot: snapshot, to: outputDirectory)
        try writeSnapshot(named: "preferences-history.png", section: .history, snapshot: snapshot, to: outputDirectory)
        try writeSnapshot(named: "preferences-dictionary.png", section: .dictionary, snapshot: snapshot, to: outputDirectory)
        try writeSnapshot(
            named: "preferences-minimum-width.png",
            section: .models,
            snapshot: snapshot,
            contentSize: NSSize(width: 620, height: 400),
            to: outputDirectory
        )
    }

    @MainActor
    private static func writeSnapshot(
        named fileName: String,
        section: PreferencesWindowController.Section,
        snapshot: PreferencesWindowController.Snapshot,
        contentSize: NSSize = NSSize(width: 680, height: 460),
        to outputDirectory: URL
    ) throws {
        let controller = PreferencesWindowController(actions: makeActions())
        guard let window = controller.window else {
            throw SnapshotError.missingWindow(fileName)
        }

        window.setContentSize(contentSize)
        controller.update(snapshot: snapshot)
        controller.selectSection(section)

        guard let contentView = window.contentView else {
            throw SnapshotError.missingContentView(fileName)
        }

        contentView.frame = NSRect(origin: .zero, size: contentSize)
        window.layoutIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        guard let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            throw SnapshotError.couldNotCreateBitmap(fileName)
        }
        contentView.cacheDisplay(in: contentView.bounds, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotEncodePNG(fileName)
        }
        try pngData.write(to: outputDirectory.appendingPathComponent(fileName), options: .atomic)
    }

    private static func makeSnapshot() -> PreferencesWindowController.Snapshot {
        PreferencesWindowController.Snapshot(
            settings: AppSettings(
                defaultModelID: ModelCatalog.parakeetModelID,
                selectedModelID: ModelCatalog.parakeetModelID,
                language: "en",
                isTranscriptHistoryEnabled: true,
                modelOffloadPolicy: .fiveMinutes,
                keepTranscriptsInClipboardHistory: true
            ),
            downloadableModels: downloadableModels,
            modelRows: modelRows,
            microphoneStatus: .authorized,
            accessibilityStatus: .denied,
            isCapturingHotkey: false,
            isModelDownloadInProgress: true,
            downloadProgressText: "42% (630/1500 MB)",
            transcriptHistory: transcriptHistory,
            transcriptHistoryLoadErrorDescription: nil,
            dictionaryEntries: dictionaryEntries,
            dictionaryLoadErrorDescription: nil,
            launchAtLoginEnabled: true
        )
    }

    @MainActor
    private static func makeActions() -> PreferencesWindowController.Actions {
        PreferencesWindowController.Actions(
            selectModel: { _ in },
            downloadModel: { _ in },
            deleteSelectedModel: {},
            cancelDownload: {},
            addModel: {},
            revealModelsFolder: {},
            openModelSource: {},
            setHotkey: {},
            requestMicrophone: {},
            requestAccessibility: {},
            setModelOffloadPolicy: { _ in },
            setKeepTranscriptsInClipboardHistory: { _ in },
            setLaunchAtLogin: { _ in },
            setTranscriptHistoryEnabled: { _ in },
            copyTranscript: { _ in },
            repasteTranscript: { _ in },
            deleteTranscripts: { _ in },
            saveDictionaryEntry: { _, _, _, completion in completion(.success(())) },
            deleteDictionaryEntries: { _, completion in completion(.success(())) },
            recoverDictionary: { completion in completion(.success(())) },
            openProjectPage: {}
        )
    }

    private static let modelRows = [
        modelRow(id: ModelCatalog.parakeetModelID, installed: true, selected: true),
        modelRow(id: "ggml-small.en", installed: true, selected: false),
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
    ]

    private static let downloadableModels = [
        downloadableModel(id: "ggml-medium"),
        downloadableModel(id: "ggml-large-v3-turbo"),
    ]

    private static let transcriptHistory = [
        TranscriptRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_782_790_000),
            text: "Follow up with Anduril about the local inference demo.",
            recordingDurationMS: 31_000,
            transcriptionLatencyMS: 1_400
        ),
        TranscriptRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            createdAt: Date(timeIntervalSince1970: 1_782_703_600),
            text: "Ship the preferences redesign after snapshot review.",
            recordingDurationMS: 19_500,
            transcriptionLatencyMS: 920
        ),
    ]

    private static let dictionaryEntries = [
        DictionaryEntry(wrong: "Anduril", correct: "Anduril"),
        DictionaryEntry(wrong: "Parakeet TDT", correct: "Parakeet TDT"),
        DictionaryEntry(wrong: "Scrawl", correct: "Scrawl"),
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
        case missingWindow(String)
        case missingContentView(String)
        case couldNotCreateBitmap(String)
        case couldNotEncodePNG(String)

        var errorDescription: String? {
            switch self {
            case let .missingWindow(fileName):
                return "Could not create preferences window for \(fileName)."
            case let .missingContentView(fileName):
                return "Could not find preferences content view for \(fileName)."
            case let .couldNotCreateBitmap(fileName):
                return "Could not create bitmap for \(fileName)."
            case let .couldNotEncodePNG(fileName):
                return "Could not encode \(fileName) as PNG."
            }
        }
    }
}
