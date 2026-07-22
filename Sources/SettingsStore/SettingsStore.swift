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

/// Upper bound on a single recording. A safety backstop that force-stops a
/// recording which never received its stop event (e.g. a missed key-up), so it
/// sits deliberately above a realistic dictation length rather than at it.
public enum MaxRecordingDuration: String, Codable, CaseIterable, Sendable {
    case oneMinute
    case twoMinutes
    case threeMinutes
    case fiveMinutes
    case tenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .threeMinutes: 180
        case .fiveMinutes: 300
        case .tenMinutes: 600
        }
    }

    public var displayName: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .threeMinutes: "3 minutes"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
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
    /// Safety backstop that force-stops a recording after this long. Defaults to
    /// 5 minutes: comfortably above a typical dictation so real recordings finish
    /// cleanly, while still bounding a recording whose stop event never arrived.
    public var maxRecordingDuration: MaxRecordingDuration
    /// Set once the app has ever observed an Accessibility grant. Lets the app tell
    /// "never granted" apart from "grant went stale after the bundle was replaced"
    /// (brew upgrade / DMG drag-over), where System Settings still shows Scrawl as
    /// enabled but `AXIsProcessTrusted()` is false and no system prompt will appear.
    public var hasEverAuthorizedAccessibility: Bool

    public init(
        defaultModelID: String = "ggml-small.en",
        selectedModelID: String = "ggml-small.en",
        language: String = "en",
        hotkey: HotkeySetting = HotkeySetting(),
        modelsDirectoryPath: String? = nil,
        isTranscriptHistoryEnabled: Bool = true,
        modelOffloadPolicy: ModelOffloadPolicy = .fiveMinutes,
        keepTranscriptsInClipboardHistory: Bool = false,
        maxRecordingDuration: MaxRecordingDuration = .fiveMinutes,
        hasEverAuthorizedAccessibility: Bool = false
    ) {
        self.defaultModelID = defaultModelID
        self.selectedModelID = selectedModelID
        self.language = language
        self.hotkey = hotkey
        self.modelsDirectoryPath = modelsDirectoryPath
        self.isTranscriptHistoryEnabled = isTranscriptHistoryEnabled
        self.modelOffloadPolicy = modelOffloadPolicy
        self.keepTranscriptsInClipboardHistory = keepTranscriptsInClipboardHistory
        self.maxRecordingDuration = maxRecordingDuration
        self.hasEverAuthorizedAccessibility = hasEverAuthorizedAccessibility
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
        case maxRecordingDuration
        case hasEverAuthorizedAccessibility
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
        maxRecordingDuration = try container.decodeIfPresent(MaxRecordingDuration.self, forKey: .maxRecordingDuration) ?? .fiveMinutes
        hasEverAuthorizedAccessibility = try container.decodeIfPresent(Bool.self, forKey: .hasEverAuthorizedAccessibility) ?? false

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
        try container.encode(maxRecordingDuration, forKey: .maxRecordingDuration)
        try container.encode(hasEverAuthorizedAccessibility, forKey: .hasEverAuthorizedAccessibility)
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
