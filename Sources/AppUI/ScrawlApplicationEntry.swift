import AppKit

public final class ScrawlApplication {
    public init() {}

    public func run() {
        do {
            let instanceLock = try SingleInstanceLock()
            if try !instanceLock.tryAcquire() {
                Self.activateExistingInstance()
                return
            }
            DelegateRetainer.shared.instanceLock = instanceLock
        } catch {
            #if DEBUG
                print("[Scrawl] Single-instance lock unavailable: \(error)")
            #endif
        }

        let app = NSApplication.shared
        let delegate = StatusBarAppDelegate(runtime: .live())

        DelegateRetainer.shared.delegate = delegate

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }

    private static func activateExistingInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jetemple.scrawl"
        let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != currentPID }

        _ = existing?.activate(options: [.activateAllWindows])
    }
}

final class DelegateRetainer {
    static let shared = DelegateRetainer()
    var delegate: NSApplicationDelegate?
    var instanceLock: SingleInstanceLock?
}
