import AudioCapture
import DictionaryStore
import Foundation
import HotkeyEngine
import Permissions
import RecordingOverlay
import SettingsStore
import TextOutput
import TranscriptionCore
import WhisperCppProvider

public struct AppRuntime {
    public let permissionManager: PermissionManager
    public let settingsStore: SettingsStore
    public let overlayController: RecordingOverlayController
    public let hotkeyStateMachine: HotkeyGestureStateMachine
    public let audioCaptureService: AudioCaptureServing
    public let textOutputTarget: TextOutputTarget
    public let dictionaryStore: any DictionaryStoring
    public let whisperProvider: any TranscriptionProvider
    public let modelsDirectoryURL: URL
    public let whisperExecutableURL: URL

    public init(
        permissionManager: PermissionManager,
        settingsStore: SettingsStore,
        overlayController: RecordingOverlayController,
        hotkeyStateMachine: HotkeyGestureStateMachine,
        audioCaptureService: AudioCaptureServing,
        textOutputTarget: TextOutputTarget,
        dictionaryStore: any DictionaryStoring,
        whisperProvider: any TranscriptionProvider,
        modelsDirectoryURL: URL,
        whisperExecutableURL: URL
    ) {
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        self.overlayController = overlayController
        self.hotkeyStateMachine = hotkeyStateMachine
        self.audioCaptureService = audioCaptureService
        self.textOutputTarget = textOutputTarget
        self.dictionaryStore = dictionaryStore
        self.whisperProvider = whisperProvider
        self.modelsDirectoryURL = modelsDirectoryURL
        self.whisperExecutableURL = whisperExecutableURL
    }

    public static func live() -> AppRuntime {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsStore = SettingsStore()
        let settings = settingsStore.load()
        let appSupportDirectory = resolveAppSupportDirectory(home: home)
        let modelsDir = resolveModelsDirectory(appSupportDirectory: appSupportDirectory, settings: settings)
        let executableURL = resolveWhisperExecutable(home: home)
        let dictionaryURL = appSupportDirectory.appending(path: "dictionary.json")

        return AppRuntime(
            permissionManager: PermissionManager(),
            settingsStore: settingsStore,
            overlayController: RecordingOverlayController(),
            hotkeyStateMachine: HotkeyGestureStateMachine(),
            audioCaptureService: AudioCaptureService(),
            textOutputTarget: PasteboardTextOutput(),
            dictionaryStore: JSONDictionaryStore(fileURL: dictionaryURL),
            whisperProvider: WhisperCppProvider(
                config: WhisperCppConfig(
                    executableURL: executableURL,
                    modelsDirectoryURL: modelsDir
                )
            ),
            modelsDirectoryURL: modelsDir,
            whisperExecutableURL: executableURL
        )
    }

    private static func resolveWhisperExecutable(home: URL) -> URL {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment
        if let override = env["SCRAWL_WHISPER_EXECUTABLE"], !override.isEmpty {
            return URL(filePath: override)
        }

        if let pathValue = env["PATH"], !pathValue.isEmpty {
            let candidatesFromPath = pathValue
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0)).appendingPathComponent("whisper-cli") }
            if let fromPath = candidatesFromPath.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
                return fromPath
            }
        }

        if let override = env["WHISPER_CPP_EXECUTABLE"], !override.isEmpty {
            return URL(filePath: override)
        }

        let candidates = [
            URL(filePath: "/opt/homebrew/bin/whisper-cli"),
            URL(filePath: "/usr/local/bin/whisper-cli"),
            URL(filePath: "/usr/bin/whisper-cli")
        ]

        if let existing = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return existing
        }
        return candidates[0]
    }

    private static func resolveModelsDirectory(appSupportDirectory: URL, settings: AppSettings) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["SCRAWL_MODELS_DIR"], !override.isEmpty {
            return URL(filePath: override)
        }
        if let genericOverride = env["WHISPER_MODELS_DIR"], !genericOverride.isEmpty {
            return URL(filePath: genericOverride)
        }
        if let configured = settings.modelsDirectoryPath, !configured.isEmpty {
            return URL(filePath: configured)
        }
        return appSupportDirectory.appending(path: "models")
    }

    private static func resolveAppSupportDirectory(home: URL) -> URL {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base.appending(path: "Scrawl")
        }
        return home.appending(path: ".local/share/scrawl")
    }
}
