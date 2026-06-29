import AudioCapture
import DictionaryStore
import Foundation
import HotkeyEngine
import Metal
import Permissions
import RecordingOverlay
import SettingsStore
import TextOutput
import TranscriptHistoryStore
import TranscriptionCore
import ParakeetProvider
import WhisperCppProvider

public struct AppRuntime {
    public let permissionManager: PermissionManager
    public let settingsStore: SettingsStore
    public let overlayController: RecordingOverlayController
    public let hotkeyStateMachine: HotkeyGestureStateMachine
    public let audioCaptureService: AudioCaptureServing
    public let textOutputTarget: TextOutputTarget
    public let dictionaryStore: any DictionaryStoring
    public let transcriptHistoryStore: any TranscriptHistoryStoring
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
        transcriptHistoryStore: any TranscriptHistoryStoring = InMemoryTranscriptHistoryStore(),
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
        self.transcriptHistoryStore = transcriptHistoryStore
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
        let recommendedDefaultModelID = resolveRecommendedDefaultModelID()
        let threadCount = resolveWhisperThreadCount()
        let dictionaryURL = appSupportDirectory.appending(path: "dictionary.json")
        let historyURL = appSupportDirectory.appending(path: "history.json")

        let whisperProvider = WhisperCppProvider(
            config: WhisperCppConfig(
                executableURL: executableURL,
                modelsDirectoryURL: modelsDir,
                disableGPU: disableGPU,
                threads: threadCount,
                idleOffloadSeconds: settings.modelOffloadPolicy.idleSeconds
            )
        )
        #if arch(arm64)
        let parakeetProvider: (any TranscriptionProvider)? = ParakeetTranscriptionProvider()
        #else
        let parakeetProvider: (any TranscriptionProvider)? = nil
        #endif

        return AppRuntime(
            permissionManager: PermissionManager(),
            settingsStore: settingsStore,
            overlayController: RecordingOverlayController(),
            hotkeyStateMachine: HotkeyGestureStateMachine(),
            audioCaptureService: AudioCaptureService(),
            textOutputTarget: PasteboardTextOutput(),
            dictionaryStore: JSONDictionaryStore(fileURL: dictionaryURL),
            transcriptHistoryStore: JSONTranscriptHistoryStore(fileURL: historyURL),
            whisperProvider: RoutingTranscriptionProvider(
                whisperProvider: whisperProvider,
                parakeetProvider: parakeetProvider
            ),
            modelsDirectoryURL: modelsDir,
            whisperExecutableURL: executableURL,
            disableGPU: disableGPU,
            recommendedDefaultModelID: recommendedDefaultModelID
        )
    }

    private static func resolveWhisperExecutable(home _: URL) -> URL {
        let trustedDirs = [
            URL(filePath: "/opt/homebrew/bin"),
            URL(filePath: "/usr/local/bin"),
            URL(filePath: "/usr/bin"),
        ]
        return resolveWhisperExecutable(
            environment: ProcessInfo.processInfo.environment,
            trustedDirs: trustedDirs
        )
    }

    /// Injectable overload used in tests. Resolution order:
    ///   1. SCRAWL_WHISPER_EXECUTABLE — absolute paths only
    ///   2. WHISPER_CPP_EXECUTABLE    — absolute paths only
    ///   3. Trusted directories (checked in order)
    ///   4. Fallback: first trusted dir / whisper-cli (binary may not exist)
    /// The general PATH scan is intentionally absent: a binary planted in any
    /// writable early-PATH directory would otherwise silently receive all raw
    /// recordings under Scrawl's TCC grants.
    static func resolveWhisperExecutable(
        environment env: [String: String],
        trustedDirs: [URL]
    ) -> URL {
        let fileManager = FileManager.default

        // 1. SCRAWL_WHISPER_EXECUTABLE — absolute path only
        if let override = env["SCRAWL_WHISPER_EXECUTABLE"],
           !override.isEmpty,
           override.hasPrefix("/")
        {
            return URL(filePath: override)
        }

        // 2. WHISPER_CPP_EXECUTABLE — absolute path only
        if let override = env["WHISPER_CPP_EXECUTABLE"],
           !override.isEmpty,
           override.hasPrefix("/")
        {
            return URL(filePath: override)
        }

        // 3. Trusted directories
        for dir in trustedDirs {
            let candidate = dir.appending(path: "whisper-cli")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // 4. Fallback: first trusted dir (or a default if list is empty)
        let fallbackDir = trustedDirs.first ?? URL(filePath: "/opt/homebrew/bin")
        return fallbackDir.appending(path: "whisper-cli")
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
            "WHISPER_NO_GPU",
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
            "WHISPER_THREADS",
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

    static func resolveRecommendedDefaultModelID() -> String {
        #if arch(arm64)
        return TranscriptionModelID.parakeetV3
        #else
        // First-run onboarding favors a fast, lightweight download. `small.en` (466 MB) is far
        // smaller and faster than the multilingual `medium` (1.5 GB), and the app is English-only
        // today, so `medium` would be strictly heavier with no benefit. Larger/multilingual models
        // remain one-click upgrades in the Models menu.
        return "ggml-small.en"
        #endif
    }

    private static func parseEnvironmentBool(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            true
        case "0", "false", "no", "n", "off":
            false
        default:
            nil
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
