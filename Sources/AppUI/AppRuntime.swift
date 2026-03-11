import AudioCapture
import DictionaryStore
import Foundation
import HotkeyEngine
import Metal
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
    public let disableGPU: Bool
    public let recommendedDefaultModelID: String

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
        whisperExecutableURL: URL,
        disableGPU: Bool,
        recommendedDefaultModelID: String
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
        self.disableGPU = disableGPU
        self.recommendedDefaultModelID = recommendedDefaultModelID
    }

    public static func live() -> AppRuntime {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsStore = SettingsStore()
        let settings = settingsStore.load()
        let appSupportDirectory = resolveAppSupportDirectory(home: home)
        let modelsDir = resolveModelsDirectory(appSupportDirectory: appSupportDirectory, settings: settings)
        let executableURL = resolveWhisperExecutable(home: home)
        let disableGPU = resolveDisableGPU()
        let recommendedDefaultModelID = resolveRecommendedDefaultModelID(disableGPU: disableGPU)
        let threadCount = resolveWhisperThreadCount()
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
                    modelsDirectoryURL: modelsDir,
                    disableGPU: disableGPU,
                    threads: threadCount
                )
            ),
            modelsDirectoryURL: modelsDir,
            whisperExecutableURL: executableURL,
            disableGPU: disableGPU,
            recommendedDefaultModelID: recommendedDefaultModelID
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

    private static func resolveDisableGPU() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let keys = [
            "SCRAWL_DISABLE_GPU",
            "WHISPER_CPP_NO_GPU",
            "WHISPER_NO_GPU"
        ]

        for key in keys {
            guard let rawValue = env[key], !rawValue.isEmpty else {
                continue
            }
            if let value = parseEnvironmentBool(rawValue) {
                return value
            }
        }

        return !hasSupportedMetalDevice()
    }

    private static func resolveWhisperThreadCount() -> Int? {
        let env = ProcessInfo.processInfo.environment
        let keys = [
            "SCRAWL_WHISPER_THREADS",
            "WHISPER_CPP_THREADS",
            "WHISPER_THREADS"
        ]

        for key in keys {
            guard let rawValue = env[key], !rawValue.isEmpty else {
                continue
            }
            if let threadCount = Int(rawValue), threadCount > 0 {
                return threadCount
            }
        }

        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        guard cpuCount > 0 else {
            return nil
        }
        return max(4, min(cpuCount, 8))
    }

    private static func resolveRecommendedDefaultModelID(disableGPU: Bool) -> String {
        if disableGPU {
            return "ggml-small.en"
        }
        return "ggml-medium"
    }

    private static func parseEnvironmentBool(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }

    private static func hasSupportedMetalDevice() -> Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    private static func resolveAppSupportDirectory(home: URL) -> URL {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return base.appending(path: "Scrawl")
        }
        return home.appending(path: ".local/share/scrawl")
    }
}
