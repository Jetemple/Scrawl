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
        .library(name: "ParakeetProvider", targets: ["ParakeetProvider"]),
        .library(name: "WhisperCppProvider", targets: ["WhisperCppProvider"]),
        .library(name: "TextOutput", targets: ["TextOutput"]),
        .library(name: "DictionaryStore", targets: ["DictionaryStore"]),
        .library(name: "TranscriptHistoryStore", targets: ["TranscriptHistoryStore"]),
        .library(name: "SettingsStore", targets: ["SettingsStore"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "RecordingOverlay", targets: ["RecordingOverlay"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "a95ec26ee05f19b5f6e69c62e1d4fae420537730"
        )
    ],
    targets: [
        .executableTarget(
            name: "ScrawlApp",
            dependencies: [
                "AppUI"
            ],
            linkerSettings: [
                // Embed the app Info.plist into the executable so `Bundle.main` reports the
                // real version even when launched as a bare binary via `swift run`/`make run`
                // (no .app bundle). Installed bundles still read their own Contents/Info.plist,
                // which takes precedence. Single source of truth: Config/ScrawlApp-Info.plist.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Config/ScrawlApp-Info.plist"
                ])
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
                "ParakeetProvider",
                "WhisperCppProvider"
            ]
        ),
        .target(name: "HotkeyEngine"),
        .target(name: "AudioCapture"),
        .target(name: "TranscriptionCore"),
        .target(
            name: "ParakeetProvider",
            dependencies: [
                "TranscriptionCore",
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
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
            name: "ParakeetProviderTests",
            dependencies: [
                "ParakeetProvider"
            ],
            resources: [
                .copy("Fixtures/clip5.wav")
            ]
        ),
        .testTarget(
            name: "RoutingTranscriptionProviderTests",
            dependencies: [
                "ParakeetProvider",
                "TranscriptionCore"
            ]
        ),
        .testTarget(
            name: "TextOutputTests",
            dependencies: [
                "TextOutput"
            ]
        ),
        .testTarget(
            name: "RecordingOverlayTests",
            dependencies: [
                "RecordingOverlay"
            ]
        )
    ]
)
