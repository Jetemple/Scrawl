/// Collapses bursts of refresh requests into a single execution.
///
/// One user action (e.g. selecting a model) funnels through several helpers that each
/// end with a preferences-window refresh; rebuilding the window three times for one
/// click is the measured source of the model-switch lag. Wrapping the action in
/// `batch(_:)` defers every `request()` inside it and performs the refresh once at
/// the end. Outside a batch, `request()` performs immediately, so call sites keep
/// their synchronous behavior. Not thread-safe: intended for main-thread UI refresh.
final class CoalescedRefresh {
    private let perform: () -> Void
    private var batchDepth = 0
    private var isRefreshPending = false

    init(perform: @escaping () -> Void) {
        self.perform = perform
    }

    /// Performs the refresh now, or defers it to the end of the enclosing `batch(_:)`.
    func request() {
        guard batchDepth > 0 else {
            perform()
            return
        }
        isRefreshPending = true
    }

    /// Runs `body`; requests made inside are collapsed into at most one refresh,
    /// executed when the outermost batch ends. Nested batches fold into the outermost.
    func batch(_ body: () -> Void) {
        batchDepth += 1
        body()
        batchDepth -= 1
        guard batchDepth == 0, isRefreshPending else { return }
        isRefreshPending = false
        perform()
    }
}
