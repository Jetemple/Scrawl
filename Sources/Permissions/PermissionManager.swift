import AVFoundation
import ApplicationServices
import Foundation

public enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

public final class PermissionManager: @unchecked Sendable {
    public init() {}

    public func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    public func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    public func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .authorized : .denied
    }

    @discardableResult
    public func requestAccessibilityAccess(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
