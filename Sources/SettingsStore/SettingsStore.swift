import Foundation

public enum ModelOffloadPolicy: String, Codable, CaseIterable, Sendable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case never

    public var idleSeconds: TimeInterval? {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .never: nil
        }
    }

    public var displayName: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .never: "Never"
        }
    }
}

public struct HotkeySetting: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var isModifierKey: Bool
    public var displayName: String

    public init(
        keyCode: UInt16 = 61,
        isModifierKey: Bool = true,
        displayName: String = "Right \u{2325} Option"
    ) {
        self.keyCode = keyCode
        self.isModifierKey = isModifierKey
        self.displayName = displayName
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var defaultModelID: String
    public var selectedModelID: String
    public var language: String
    public var hotkey: HotkeySetting
    public var modelsDirectoryPath: String?
    public var isTranscriptHistoryEnabled: Bool
    public var modelOffloadPolicy: ModelOffloadPolicy
    /// When `true`, transcripts are written to the pasteboard without the
    /// `org.nspasteboard.TransientType` / `ConcealedType` markers so clipboard
    /// managers (e.g. Raycast, Paste) can record them.  Defaults to `false`.
    public var keepTranscriptsInClipboardHistory: Bool

    public init(
        defaultModelID: String = "ggml-small.en",
        selectedModelID: String = "ggml-small.en",
        language: String = "en",
        hotkey: HotkeySetting = HotkeySetting(),
        modelsDirectoryPath: String? = nil,
        isTranscriptHistoryEnabled: Bool = true,
        modelOffloadPolicy: ModelOffloadPolicy = .fiveMinutes,
        keepTranscriptsInClipboardHistory: Bool = false
    ) {
        self.defaultModelID = defaultModelID
        self.selectedModelID = selectedModelID
        self.language = language
        self.hotkey = hotkey
        self.modelsDirectoryPath = modelsDirectoryPath
        self.isTranscriptHistoryEnabled = isTranscriptHistoryEnabled
        self.modelOffloadPolicy = modelOffloadPolicy
        self.keepTranscriptsInClipboardHistory = keepTranscriptsInClipboardHistory
    }

    public var modelID: String {
        selectedModelID
    }

    enum CodingKeys: String, CodingKey {
        case defaultModelID
        case selectedModelID
        case language
        case hotkey
        case hotkeyDescription
        case modelsDirectoryPath
        case isTranscriptHistoryEnabled
        case modelOffloadPolicy
        case keepTranscriptsInClipboardHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        defaultModelID = try container.decodeIfPresent(String.self, forKey: .defaultModelID) ?? "ggml-small.en"
        selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID) ?? defaultModelID
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        modelsDirectoryPath = try container.decodeIfPresent(String.self, forKey: .modelsDirectoryPath)
        isTranscriptHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTranscriptHistoryEnabled) ?? true
        modelOffloadPolicy = try container.decodeIfPresent(ModelOffloadPolicy.self, forKey: .modelOffloadPolicy) ?? .fiveMinutes
        keepTranscriptsInClipboardHistory = try container.decodeIfPresent(Bool.self, forKey: .keepTranscriptsInClipboardHistory) ?? false

        if let hotkey = try container.decodeIfPresent(HotkeySetting.self, forKey: .hotkey) {
            self.hotkey = hotkey
        } else {
            let description = try container.decodeIfPresent(String.self, forKey: .hotkeyDescription) ?? "Right \u{2325} Option"
            hotkey = HotkeySetting(keyCode: 61, isModifierKey: true, displayName: description)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultModelID, forKey: .defaultModelID)
        try container.encode(selectedModelID, forKey: .selectedModelID)
        try container.encode(language, forKey: .language)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encodeIfPresent(modelsDirectoryPath, forKey: .modelsDirectoryPath)
        try container.encode(isTranscriptHistoryEnabled, forKey: .isTranscriptHistoryEnabled)
        try container.encode(modelOffloadPolicy, forKey: .modelOffloadPolicy)
        try container.encode(keepTranscriptsInClipboardHistory, forKey: .keepTranscriptsInClipboardHistory)
    }
}

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "scrawl.settings.v1"
    private let transcriptHistoryEnabledKey = "scrawl.settings.transcriptHistoryEnabled"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func hasStoredSettings() -> Bool {
        lock.withLock {
            defaults.data(forKey: key) != nil
        }
    }

    public func load() -> AppSettings {
        lock.withLock {
            loadUnlocked()
        }
    }

    public func save(_ settings: AppSettings) throws {
        try lock.withLock {
            try saveUnlocked(settings)
        }
    }

    /// Atomically loads, transforms, and saves settings in a single critical section.
    /// Use instead of a manual load → mutate → save sequence to prevent interleaved writes.
    public func mutate(_ transform: (inout AppSettings) -> Void) throws {
        try lock.withLock {
            var settings = loadUnlocked()
            transform(&settings)
            try saveUnlocked(settings)
        }
    }

    private func loadUnlocked() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return AppSettings()
        }

        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return decoded
        }

        var settings = AppSettings()
        if defaults.object(forKey: transcriptHistoryEnabledKey) != nil {
            settings.isTranscriptHistoryEnabled = defaults.bool(forKey: transcriptHistoryEnabledKey)
        } else {
            settings.isTranscriptHistoryEnabled = false
        }
        return settings
    }

    private func saveUnlocked(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
        defaults.set(settings.isTranscriptHistoryEnabled, forKey: transcriptHistoryEnabledKey)
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
