@testable import AppUI
import AudioCapture
import DictionaryStore
import Foundation
import HotkeyEngine
import Permissions
import RecordingOverlay
import SettingsStore
import TextOutput
import TranscriptionCore
import XCTest

final class AppRuntimeResolutionTests: XCTestCase {
    func testRecommendedDefaultModelIsLightweightEnglishForFastOnboarding() {
        #if arch(arm64)
        XCTAssertEqual(AppRuntime.resolveRecommendedDefaultModelID(), "parakeet-v3")
        #else
        XCTAssertEqual(AppRuntime.resolveRecommendedDefaultModelID(), "ggml-small.en")
        #endif
    }

    func testPublicInitializerDefaultsToInMemoryTranscriptHistoryStore() throws {
        let runtime = try AppRuntime(
            permissionManager: PermissionManager(),
            settingsStore: SettingsStore(defaults: XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))),
            overlayController: RecordingOverlayController(),
            hotkeyStateMachine: HotkeyGestureStateMachine(),
            audioCaptureService: StubAudioCaptureService(),
            textOutputTarget: StubTextOutputTarget(),
            dictionaryStore: InMemoryDictionaryStore(),
            whisperProvider: StubTranscriptionProvider(),
            modelsDirectoryURL: URL(filePath: "/tmp/models"),
            whisperExecutableURL: URL(filePath: "/tmp/whisper"),
            disableGPU: false,
            recommendedDefaultModelID: "model"
        )

        XCTAssertTrue(runtime.transcriptHistoryStore.records().isEmpty)
    }

    // MARK: - Trusted-directory resolution tests

    func testScrawlWhisperExecutableEnvOverrideIsCheckedFirst() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a fake whisper-cli in the env-override path
        let overridePath = tmpDir.appending(path: "my-whisper").path
        FileManager.default.createFile(atPath: overridePath, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: overridePath)

        // PATH also contains a whisper-cli — it should be ignored
        let pathDir = tmpDir.appending(path: "pathbin")
        try FileManager.default.createDirectory(at: pathDir, withIntermediateDirectories: true)
        let pathCli = pathDir.appending(path: "whisper-cli").path
        FileManager.default.createFile(atPath: pathCli, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pathCli)

        let env = [
            "SCRAWL_WHISPER_EXECUTABLE": overridePath,
            "PATH": pathDir.path,
        ]
        let result = AppRuntime.resolveWhisperExecutable(environment: env, trustedDirs: [])
        XCTAssertEqual(result.path, overridePath)
    }

    func testWhisperCppExecutableEnvOverrideIsCheckedSecond() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let overridePath = tmpDir.appending(path: "my-whisper").path
        FileManager.default.createFile(atPath: overridePath, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: overridePath)

        // SCRAWL_WHISPER_EXECUTABLE is absent; WHISPER_CPP_EXECUTABLE should win
        let env = ["WHISPER_CPP_EXECUTABLE": overridePath]
        let result = AppRuntime.resolveWhisperExecutable(environment: env, trustedDirs: [])
        XCTAssertEqual(result.path, overridePath)
    }

    func testBinaryInPathDirIsNotFoundWhenPathScanIsDropped() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Attacker plants whisper-cli in a PATH dir
        let pathDir = tmpDir.appending(path: "evil-bin")
        try FileManager.default.createDirectory(at: pathDir, withIntermediateDirectories: true)
        let pathCli = pathDir.appending(path: "whisper-cli").path
        FileManager.default.createFile(atPath: pathCli, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pathCli)

        // No env overrides; pass the evil dir as part of PATH but NOT as trusted
        let env = ["PATH": pathDir.path]
        let result = AppRuntime.resolveWhisperExecutable(environment: env, trustedDirs: [])
        // Must not return the planted binary
        XCTAssertNotEqual(result.path, pathCli)
    }

    func testTrustedDirIsSearchedAfterEnvOverrides() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Place whisper-cli in a trusted dir
        let trustedDir = tmpDir.appending(path: "trusted-bin")
        try FileManager.default.createDirectory(at: trustedDir, withIntermediateDirectories: true)
        let trustedCli = trustedDir.appending(path: "whisper-cli").path
        FileManager.default.createFile(atPath: trustedCli, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trustedCli)

        let result = AppRuntime.resolveWhisperExecutable(environment: [:], trustedDirs: [trustedDir])
        XCTAssertEqual(result.path, trustedCli)
    }

    func testRelativePathEnvOverrideIsIgnored() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Trusted dir has a binary
        let trustedDir = tmpDir.appending(path: "trusted")
        try FileManager.default.createDirectory(at: trustedDir, withIntermediateDirectories: true)
        let trustedCli = trustedDir.appending(path: "whisper-cli").path
        FileManager.default.createFile(atPath: trustedCli, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trustedCli)

        // Relative path override must be ignored
        let env = ["SCRAWL_WHISPER_EXECUTABLE": "bin/whisper-cli"]
        let result = AppRuntime.resolveWhisperExecutable(environment: env, trustedDirs: [trustedDir])
        // Should fall through to trusted dir, not use relative path
        XCTAssertEqual(result.path, trustedCli)
    }

    func testRelativeWhisperCppExecutableOverrideIsIgnored() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let trustedDir = tmpDir.appending(path: "trusted")
        try FileManager.default.createDirectory(at: trustedDir, withIntermediateDirectories: true)
        let trustedCli = trustedDir.appending(path: "whisper-cli").path
        FileManager.default.createFile(atPath: trustedCli, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trustedCli)

        let env = ["WHISPER_CPP_EXECUTABLE": "relative/whisper-cli"]
        let result = AppRuntime.resolveWhisperExecutable(environment: env, trustedDirs: [trustedDir])
        XCTAssertEqual(result.path, trustedCli)
    }

    func testFallsBackToFirstTrustedDirWhenNoBinaryFound() {
        let result = AppRuntime.resolveWhisperExecutable(
            environment: [:],
            trustedDirs: [
                URL(filePath: "/opt/homebrew/bin"),
                URL(filePath: "/usr/local/bin"),
                URL(filePath: "/usr/bin"),
            ]
        )
        // No binary exists in any trusted dir: fall back to first trusted dir / whisper-cli
        XCTAssertEqual(result.path, "/opt/homebrew/bin/whisper-cli")
    }
}

private struct StubAudioCaptureService: AudioCaptureServing {
    func startCapture() throws {}
    func stopCapture() throws -> URL {
        URL(filePath: "/tmp/audio.wav")
    }

    func currentAveragePower() -> Float? { nil }
}

private struct StubTextOutputTarget: TextOutputTarget {
    func output(_: String, markPrivate _: Bool) async throws {}
}

private struct StubTranscriptionProvider: TranscriptionProvider {
    func transcribe(_: TranscriptionRequest) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", latencyMS: 0)
    }
}
