/// Pure lifecycle decisions for the record → stop → finalize path, kept side-effect-free
/// so the re-entrancy guards and the grace window can be unit-tested without driving AppKit.
///
/// A push-to-talk key is often released the instant the last word ends — or a hair before it
/// does — so hold-release keeps the microphone open for a short grace window before the
/// recorder finalizes the file, letting a trailing word still land. Every other stop is either
/// deliberate (manual, toggle) or forced (system sleep, safety timeout): those finalize at
/// once, both to avoid needless latency and because lingering past a sleep-driven stop would
/// keep the mic live exactly when it must not be.
///
/// `isHoldRelease` describes the *stop*, not the recording: only a genuine push-to-talk key
/// release earns the grace window. A sleep or safety timeout that stops a hold recording is
/// forced, not a key release, so it finalizes now — and a forced stop preempts an already
/// running grace window rather than being swallowed, which is what actually guarantees the mic
/// is closed before the machine sleeps.
enum CaptureStopDecision: Equatable {
    /// No capture is active, or one is already finalizing — ignore the stop request.
    case ignore
    /// Finalize the recording immediately.
    case finalizeNow
    /// Keep the mic open for the grace window, then finalize.
    case finalizeAfterGrace

    static func decide(
        hasActiveCapture: Bool,
        isFinishing: Bool,
        isHoldRelease: Bool,
        isForced: Bool
    ) -> CaptureStopDecision {
        guard hasActiveCapture else {
            return .ignore
        }
        // A grace window is already running. A forced stop (sleep, safety timeout) must preempt
        // it and finalize now so the mic does not linger into sleep; any other stop is a no-op
        // because the finalize is already scheduled.
        if isFinishing {
            return isForced ? .finalizeNow : .ignore
        }
        return isHoldRelease ? .finalizeAfterGrace : .finalizeNow
    }

    /// A new capture may begin only when nothing is recording and no finalize is pending;
    /// starting during the grace window would race the in-flight finalize and re-open the mic
    /// against a recorder that is about to be torn down.
    static func canBeginCapture(hasActiveCapture: Bool, isFinishing: Bool) -> Bool {
        !hasActiveCapture && !isFinishing
    }
}
