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
        // First-run onboarding should recommend the small English model regardless of GPU:
        // it is far smaller than `medium` and the app's language is English-only today, so the
        // multilingual `medium` model would be strictly heavier/slower with no benefit.
        XCTAssertEqual(AppRuntime.resolveRecommendedDefaultModelID(), "ggml-small.en")
    }

    func testPublicInitializerDefaultsToInMemoryTranscriptHistoryStore() {
        let runtime = AppRuntime(
            permissionManager: PermissionManager(),
            settingsStore: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
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
}

private struct StubAudioCaptureService: AudioCaptureServing {
    func startCapture() throws {}
    func stopCapture() throws -> URL { URL(filePath: "/tmp/audio.wav") }
}

private struct StubTextOutputTarget: TextOutputTarget {
    func output(_ text: String) async throws {}
}

private struct StubTranscriptionProvider: TranscriptionProvider {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", latencyMS: 0)
    }
}
