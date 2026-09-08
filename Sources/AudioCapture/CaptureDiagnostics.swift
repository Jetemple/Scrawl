import AVFoundation
import Foundation

/// Opt-in instrumentation for the recorder, enabled with `SCRAWL_CAPTURE_DIAGNOSTICS=1`.
/// It exists to answer one question when a transcript comes back with its tail missing: was
/// the audio short, or was the audio complete and the transcriber dropped the end?
///
/// It sits at the recorder boundary rather than in the app so it can compare three numbers
/// that only `AudioCaptureService` holds together — how long the microphone was open in wall
/// clock, how much audio `AVAudioRecorder` says it captured, and how much audio the finished
/// file actually contains — and it keeps a copy of the WAV, because the finalize path deletes
/// the working file as soon as transcription ends and there is otherwise nothing left to
/// replay. Match a line to its transcript through the transcript history's timestamps.
///
/// Disabled by default and entirely side-effect-free when the variable is unset: every
/// recording is kept on disk while it is on, so it is a debugging tool, not a setting.
/// `SCRAWL_CAPTURE_DIAGNOSTICS_DIR` redirects the log and the WAV copies elsewhere.
public enum CaptureDiagnostics {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SCRAWL_CAPTURE_DIAGNOSTICS"] != nil
    }

    /// Copy the finished recording aside and log the microphone's open time against the audio
    /// that came back. `recorderSeconds` is `AVAudioRecorder.currentTime` read just before the
    /// stop: a gap between it and `wallSeconds` means the recorder stopped capturing early,
    /// while a gap between it and the file means the last buffers never reached disk.
    @discardableResult
    public static func recordCapture(
        audioURL: URL,
        wallSeconds: Double,
        recorderSeconds: Double
    ) -> String? {
        guard isEnabled, let directory = diagnosticsDirectory() else { return nil }

        let id = timestamp()
        let savedURL = directory.appendingPathComponent("capture-\(id).wav")
        try? FileManager.default.copyItem(at: audioURL, to: savedURL)

        let fileSeconds = audioDurationSeconds(of: audioURL)
        append(to: directory, line: [
            ("capture", id),
            ("wall", seconds(wallSeconds)),
            ("recorder", seconds(recorderSeconds)),
            ("file", fileSeconds.map(seconds) ?? "unreadable"),
            ("missing", fileSeconds.map { seconds(wallSeconds - $0) } ?? "unknown"),
            ("wav", savedURL.lastPathComponent),
        ].map { "\($0.0)=\($0.1)" }.joined(separator: " "))
        return id
    }

    /// Log a push-to-talk key transition. A `wall`/`file` pair cannot see a microphone that
    /// closed early, because both are measured to whatever stop actually happened — an early
    /// release simply makes the whole recording short and the gap stay at zero. These lines
    /// are what expose it: a `down` with no speech-length `up` after it, or an `up` logged
    /// while the speaker was mid-sentence, names a spurious release directly. `flag` and
    /// `keyState` are the two independent sources the monitor ORs together, logged apart so a
    /// disagreement between them is visible.
    public static func recordHotkeyTransition(isDown: Bool, flag: Bool, keyState: Bool) {
        guard isEnabled, let directory = diagnosticsDirectory() else { return }
        append(to: directory, line: [
            ("hotkey", isDown ? "down" : "up"),
            ("at", timestamp()),
            ("flag", String(flag)),
            ("keyState", String(keyState)),
        ].map { "\($0.0)=\($0.1)" }.joined(separator: " "))
    }

    /// Log a recording the capture service rejected, so a dropped one is not silently absent.
    public static func recordRejection(wallSeconds: Double, error: Error) {
        guard isEnabled, let directory = diagnosticsDirectory() else { return }
        append(to: directory, line: [
            ("capture", timestamp()),
            ("wall", seconds(wallSeconds)),
            ("rejected", String(describing: error)),
        ].map { "\($0.0)=\($0.1)" }.joined(separator: " "))
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }

    private static func audioDurationSeconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return nil }
        return Double(file.length) / sampleRate
    }

    private static func diagnosticsDirectory() -> URL? {
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["SCRAWL_CAPTURE_DIAGNOSTICS_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            directory = base
                .appendingPathComponent("Scrawl", isDirectory: true)
                .appendingPathComponent("CaptureDiagnostics", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let timestampLock = NSLock()
    private static let appendLock = NSLock()

    private static func timestamp() -> String {
        timestampLock.lock()
        defer { timestampLock.unlock() }
        return DateFormatter.captureTimestamp.string(from: .now)
    }

    private static func append(to directory: URL, line: String) {
        appendLock.lock()
        defer { appendLock.unlock() }
        let logURL = directory.appendingPathComponent("capture-diagnostics.log")
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}

private extension DateFormatter {
    /// The timestamp doubles as a filename, so it carries no colons and no spaces.
    static let captureTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
