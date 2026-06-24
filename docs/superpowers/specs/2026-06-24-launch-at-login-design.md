# Launch at login

## Summary

Add a "Launch at login" checkbox to Settings → General that starts Scrawl
automatically when the user signs in. Scrawl is an `LSUIElement` menu-bar app,
so launching at login simply makes its menu-bar icon appear after sign-in with
no window.

This ships as part of v0.0.10 (PR #10).

## Mechanism

Use `SMAppService.mainApp` from the `ServiceManagement` framework.

- Scrawl targets macOS 14 (`Package.swift`: `.macOS(.v14)`,
  `LSMinimumSystemVersion` 14.0) and is **not** sandboxed (entitlements grant
  only `com.apple.security.device.audio-input`). `SMAppService` requires macOS
  13+, so it is available and is the modern, correct API for the main app — no
  helper bundle and no legacy `LSSharedFileList`.
- Enable: `try SMAppService.mainApp.register()`
- Disable: `try SMAppService.mainApp.unregister()`
- Current state: `SMAppService.mainApp.status` (`.enabled`, `.notRegistered`,
  `.requiresApproval`, `.notFound`)

## Source of truth

The OS is the single source of truth. We do **not** add a `launchAtLogin` field
to `AppSettings`.

The login-item registration already lives in the OS and persists across
launches on its own. Storing a duplicate bool in `AppSettings` would let the two
drift — e.g. the user removes Scrawl under System Settings → General → Login
Items while our stored bool still reads `true`. Instead the checkbox reflects
`SMAppService.mainApp.status == .enabled`, read live each time the General tab
is shown.

This is a deliberate departure from the "all preferences live in `AppSettings`"
pattern, justified by login items being OS-owned state.

## Components and seams

### `Sources/AppUI/LoginItem.swift` (new)

A small protocol seam so the wiring is testable without touching real OS state:

```swift
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
```

Concrete implementation `SMAppServiceLoginItem`:
- `isEnabled` returns `SMAppService.mainApp.status == .enabled`
- `setEnabled(true)` calls `register()`; `setEnabled(false)` calls `unregister()`

`SMAppServiceLoginItem` itself is not unit-tested (it touches real OS state); it
is verified manually in the installed `.app`. The protocol lets the wiring layer
be tested with a fake.

### `Sources/AppUI/PreferencesGeneralView.swift`

Follow the existing `keepTranscriptsInClipboardHistory` checkbox group exactly:

- Add `launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", …)`
  with subtitle label "Start Scrawl automatically when you sign in." grouped in
  a vertical `NSStackView`, placed in its own group below the clipboard-history
  group.
- Add `setLaunchAtLogin: (Bool) -> Void` init closure (default `{ _ in }`,
  matching the clipboard closure's defaulting).
- Add an `@objc` action that calls `setLaunchAtLogin(sender.state == .on)`.
- Extend `update(...)` with a `launchAtLoginEnabled: Bool` parameter that sets
  `launchAtLoginCheckbox.state`.

### `Sources/AppUI/PreferencesWindowController.swift`

- Add `setLaunchAtLogin: (Bool) -> Void` to the `Actions` struct.
- Pass `actions.setLaunchAtLogin` into the `PreferencesGeneralView` initializer
  (mirrors `setKeepTranscriptsInClipboardHistory` at the existing call site).

### `Sources/AppUI/ScrawlApplication.swift`

- Hold a `LoginItemControlling` (concrete `SMAppServiceLoginItem`).
- Build the `setLaunchAtLogin` action closure: on toggle, call
  `loginItem.setEnabled(...)`; on failure, revert and surface an alert (see
  Error handling).
- When refreshing/opening the General tab, pass
  `loginItem.isEnabled` into `update(launchAtLoginEnabled:)` so the checkbox
  always reflects live OS state.

## Data flow

```
checkbox toggled
  → PreferencesGeneralView.setLaunchAtLogin(Bool)
  → PreferencesWindowController.Actions.setLaunchAtLogin
  → ScrawlApplication closure
  → LoginItemControlling.setEnabled(Bool)        // SMAppService register/unregister
General tab shown
  → ScrawlApplication reads LoginItemControlling.isEnabled
  → PreferencesGeneralView.update(launchAtLoginEnabled:)
  → checkbox.state reflects SMAppService.mainApp.status
```

## Error handling

`setEnabled` can throw, and `register()` can leave the service in
`.requiresApproval` (macOS may require the user to approve login items).

- On a thrown error or a non-`.enabled` result after enabling, revert the
  checkbox to the real `isEnabled` value.
- Show a short alert explaining Scrawl could not change the login item, with an
  "Open Login Items Settings" button that deep-links to System Settings (Login
  Items pane). No silent failure.

## Placement and copy

- Settings → General tab, its own group below the clipboard-history group.
- Label: **Launch at login**
- Subtitle: **Start Scrawl automatically when you sign in.**

## Testing

Test-driven where the seam allows:

1. `PreferencesGeneralView`
   - `update(launchAtLoginEnabled: true/false)` sets `launchAtLoginCheckbox.state`.
   - Simulating the checkbox action fires `setLaunchAtLogin` with the matching
     bool.
2. Wiring closure
   - With a fake `LoginItemControlling`, toggling on/off calls
     `setEnabled(true)` / `setEnabled(false)`.
   - On a fake that throws, the checkbox reverts to `isEnabled` (no crash, no
     stuck state).

`SMAppServiceLoginItem` is verified manually in the installed `.app`.

Existing gates must stay green: full test suite (currently 307 passing, 1
skipped), SwiftFormat, SwiftLint.

## Known development limitation

`SMAppService.mainApp` needs a real, signed app bundle. Running via `swift run`
will not register a login item. Verify the feature in the installed app built by
`scripts/install-app.sh`.

## Docs

Add one feature line to the README feature list and to the PR #10 body, in the
existing voice (tight, plain, no em-dashes or filler).

## Out of scope (YAGNI)

- No menu-bar menu item for this toggle (settings checkbox only).
- No `launchAtLogin` field in `AppSettings` and no settings migration.
- No support for macOS < 14.
