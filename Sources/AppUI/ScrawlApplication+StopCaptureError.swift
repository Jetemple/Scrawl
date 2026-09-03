import AppKit
import AudioCapture
import Foundation

/// Stop-capture error handling for StatusBarAppDelegate. Lives in this
/// extension file instead of ScrawlApplication.swift: that file sits exactly
/// at the file_length error cliff (2100 code lines), so even this small helper
/// would fail `make lint` there.
extension StatusBarAppDelegate {
    @MainActor
    func handleStopCaptureError(_ error: Error, activeOrigin: RecordingOrigin) async {
        recordingOrigin = nil
        recordingStartedAt = nil
        updateRecordingActionRows()
        runtime.overlayController.setState(.idle)
        updateStatusIcon()
        setStatus("Stop error: \(describe(error))")
        if case AudioCaptureError.audioLevelTooLow = error {
            presentNoAudioCapturedMessage()
        } else if case AudioCaptureError.captureTooShort = error, activeOrigin != .manual {
            presentNoSpeechDetectedAlert()
        }
    }
}
