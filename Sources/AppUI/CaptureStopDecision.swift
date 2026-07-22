/// Pure lifecycle decisions for the record → stop → finalize path, kept side-effect-free
/// so the re-entrancy guards and the grace window can be unit-tested without driving AppKit.
///
/// A push-to-talk key is often released the instant the last word ends — or a hair before it
/// does — so hold-release keeps the microphone open for a short grace window before the
/// recorder finalizes the file, letting a trailing word still land. Every other stop is either
/// deliberate (manual, toggle) or forced (system sleep, safety timeout): those finalize at
/// once, both to avoid needless latency and because lingering past a sleep-driven stop would
/// keep the mic live exactly when it must not be.
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
        isHoldRelease: Bool
    ) -> CaptureStopDecision {
        guard hasActiveCapture, !isFinishing else {
            return .ignore
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
