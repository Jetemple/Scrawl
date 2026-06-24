import ServiceManagement

/// Controls whether Scrawl is registered as a macOS login item (starts at sign-in).
///
/// The OS owns this state. Implementations read and mutate it directly; callers
/// treat the live value as the single source of truth rather than caching it.
protocol LoginItemControlling {
    /// `true` when Scrawl is currently registered and enabled as a login item.
    var isEnabled: Bool { get }

    /// Registers (enable) or unregisters (disable) Scrawl as a login item.
    /// Throws if the OS rejects the change. Note: enabling can succeed while the
    /// system still requires user approval — check `isEnabled` afterward.
    func setEnabled(_ enabled: Bool) throws
}

/// `LoginItemControlling` backed by `SMAppService.mainApp` (macOS 13+).
struct SMAppServiceLoginItem: LoginItemControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
