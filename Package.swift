// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Scrawl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScrawlApp", targets: ["ScrawlApp"]),
        .library(name: "AppUI", targets: ["AppUI"]),
        .library(name: "HotkeyEngine", targets: ["HotkeyEngine"]),
        .library(name: "AudioCapture", targets: ["AudioCapture"]),
        .library(name: "TranscriptionCore", targets: ["TranscriptionCore"]),
        .library(name: "WhisperCppProvider", targets: ["WhisperCppProvider"]),
        .library(name: "TextOutput", targets: ["TextOutput"]),
        .library(name: "DictionaryStore", targets: ["DictionaryStore"]),
        .library(name: "TranscriptHistoryStore", targets: ["TranscriptHistoryStore"]),
        .library(name: "SettingsStore", targets: ["SettingsStore"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "RecordingOverlay", targets: ["RecordingOverlay"])
    ],
    targets: [
        .executableTarget(
            name: "ScrawlApp",
            dependencies: [
                "AppUI"
            ]
        ),
        .target(
            name: "AppUI",
            dependencies: [
                "AudioCapture",
                "DictionaryStore",
                "HotkeyEngine",
                "Permissions",
                "RecordingOverlay",
                "SettingsStore",
                "TextOutput",
                "TranscriptHistoryStore",
                "TranscriptionCore",
                "WhisperCppProvider"
            ]
        ),
        .target(name: "HotkeyEngine"),
        .target(name: "AudioCapture"),
        .target(name: "TranscriptionCore"),
        .target(
            name: "WhisperCppProvider",
            dependencies: [
                "TranscriptionCore"
            ]
        ),
        .target(name: "TextOutput"),
        .target(name: "DictionaryStore"),
        .target(name: "TranscriptHistoryStore"),
        .target(name: "SettingsStore"),
        .target(name: "Permissions"),
        .target(name: "RecordingOverlay"),
        .testTarget(
            name: "AppUITests",
            dependencies: [
                "AppUI",
                "DictionaryStore",
                "TranscriptHistoryStore",
                "SettingsStore"
            ]
        ),
        .testTarget(
            name: "HotkeyEngineTests",
            dependencies: [
                "HotkeyEngine"
            ]
        ),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: [
                "AudioCapture"
            ]
        ),
        .testTarget(
            name: "DictionaryStoreTests",
            dependencies: [
                "DictionaryStore"
            ]
        ),
        .testTarget(
            name: "TranscriptHistoryStoreTests",
            dependencies: [
                "TranscriptHistoryStore"
            ]
        ),
        .testTarget(
            name: "SettingsStoreTests",
            dependencies: [
                "SettingsStore"
            ]
        ),
        .testTarget(
            name: "WhisperCppProviderTests",
            dependencies: [
                "WhisperCppProvider"
            ]
        ),
        .testTarget(
            name: "TextOutputTests",
            dependencies: [
                "TextOutput"
            ]
        )
    ]
)
