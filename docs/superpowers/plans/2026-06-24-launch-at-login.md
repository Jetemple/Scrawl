# Launch at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Launch at login" checkbox to Settings → General that registers Scrawl as a macOS login item so it starts automatically at sign-in.

**Architecture:** A thin `LoginItemControlling` protocol wraps `SMAppService.mainApp` (register / unregister / status). The checkbox sources its state live from `SMAppService` status — the OS is the single source of truth, so there is no stored `AppSettings` field and no drift. UI wiring follows the existing `keepTranscriptsInClipboardHistory` checkbox pattern exactly: a closure on `PreferencesGeneralView`, a field on `PreferencesWindowController.Actions`, a field on `Snapshot`, and a closure built in `ScrawlApplication`.

**Tech Stack:** Swift, AppKit, `ServiceManagement` (`SMAppService`), Swift Package Manager, XCTest.

## Global Constraints

- **Deployment target:** macOS 14 (`Package.swift`: `.macOS(.v14)`). `SMAppService` needs macOS 13+, so it is available with **no `@available` guards**.
- **Source of truth:** the OS login-item registration. Do **not** add a `launchAtLogin` field to `AppSettings`. The checkbox always reflects `SMAppService.mainApp.status == .enabled`.
- **Exact copy:** checkbox label `Launch at login`; subtitle `Start Scrawl automatically when you sign in.`
- **Gates must stay green:** full test suite (currently 307 passing, 1 skipped), SwiftFormat, SwiftLint. Run `make test`, `make format` (or the SwiftFormat invocation the repo uses), and SwiftLint before each commit.
- **Git:** never add a "Co-Authored-By: Claude" trailer or any Claude credit to commits.
- **No new dependency:** `ServiceManagement` is a system framework; `import` it directly. No `Package.swift` change.

---

## File Structure

- **Create** `Sources/AppUI/LoginItem.swift` — `LoginItemControlling` protocol + `SMAppServiceLoginItem` concrete wrapper. One responsibility: the login-item OS seam.
- **Modify** `Sources/AppUI/PreferencesGeneralView.swift` — add the checkbox, subtitle, `setLaunchAtLogin` closure, `launchAtLoginEnabled` update param, `isLaunchAtLoginEnabled` accessor.
- **Modify** `Sources/AppUI/PreferencesWindowController.swift` — add `setLaunchAtLogin` to `Actions`, `launchAtLoginEnabled` to `Snapshot`, thread both through, add `generalLaunchAtLoginEnabled` accessor.
- **Modify** `Sources/AppUI/ScrawlApplication.swift` — hold a `LoginItemControlling`, build the `setLaunchAtLogin` closure with error/approval handling, fill the snapshot from `loginItem.isEnabled`.
- **Modify** `Tests/AppUITests/PreferencesWindowControllerTests.swift` — extend `makeActions`/`makeSnapshot` helpers, add the checkbox test.
- **Modify** `README.md` — one feature bullet.

---

## Task 1: Login-item seam (`LoginItem.swift`)

**Files:**
- Create: `Sources/AppUI/LoginItem.swift`

**Interfaces:**
- Produces:
  - `protocol LoginItemControlling { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) throws }`
  - `struct SMAppServiceLoginItem: LoginItemControlling` (concrete, wraps `SMAppService.mainApp`)

**Why no unit test:** `SMAppServiceLoginItem` is a thin pass-through to `SMAppService.mainApp`, which mutates real OS login-item state. There is no behavior to unit-test in isolation; it is verified manually in the installed `.app` (Task 4). The protocol exists so the *type* is substitutable, not so this wrapper can be faked in the existing test suite (the suite tests the controller/view, not `ScrawlApplication`).

- [ ] **Step 1: Create the file**

Create `Sources/AppUI/LoginItem.swift`:

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `make build`
Expected: builds cleanly. Nothing references the new types yet, so the rest of the app is unchanged.

- [ ] **Step 3: Run formatter and linter**

Run the repo's SwiftFormat and SwiftLint (e.g. `make format` / `swiftlint`). Expected: clean, no changes needed to the other files.

- [ ] **Step 4: Commit**

```bash
git add Sources/AppUI/LoginItem.swift
git commit -m "feat: add SMAppService login-item seam"
```

---

## Task 2: Wire the checkbox through the settings UI

This task adds the checkbox and threads it from the General view up to `ScrawlApplication`, including error/approval handling. Adding required fields to the `Actions` and `Snapshot` structs forces every construction site (`ScrawlApplication` + test helpers) to update in the same commit, so they all land here and the build ends green with a passing new test.

**Files:**
- Modify: `Sources/AppUI/PreferencesGeneralView.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Sources/AppUI/ScrawlApplication.swift`
- Test: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

**Interfaces:**
- Consumes (from Task 1): `LoginItemControlling`, `SMAppServiceLoginItem`.
- Produces:
  - `PreferencesGeneralView.init(..., setLaunchAtLogin: @escaping (Bool) -> Void = { _ in })`
  - `PreferencesGeneralView.update(..., launchAtLoginEnabled: Bool)`
  - `PreferencesGeneralView.isLaunchAtLoginEnabled: Bool`
  - `PreferencesWindowController.Actions.setLaunchAtLogin: (Bool) -> Void`
  - `PreferencesWindowController.Snapshot.launchAtLoginEnabled: Bool` (declared **last** in the struct)
  - `PreferencesWindowController.generalLaunchAtLoginEnabled: Bool`

- [ ] **Step 1: Write the failing test**

In `Tests/AppUITests/PreferencesWindowControllerTests.swift`, add this test after `testGeneralClipboardHistoryCheckboxReflectsSettingAndDispatchesAction`:

```swift
@MainActor
func testGeneralLaunchAtLoginCheckboxReflectsStateAndDispatchesAction() {
    var capturedValue: Bool?
    let controller = PreferencesWindowController(actions: makeActions(
        setLaunchAtLogin: { capturedValue = $0 }
    ))

    // Defaults to off.
    controller.update(snapshot: makeSnapshot())
    XCTAssertFalse(controller.generalLaunchAtLoginEnabled)

    // Reflects the live login-item state when enabled.
    controller.update(snapshot: makeSnapshot(launchAtLoginEnabled: true))
    XCTAssertTrue(controller.generalLaunchAtLoginEnabled)

    // Clicking dispatches the action.
    let contentView = controller.window?.contentView
    let checkbox = contentView?.button(titled: "Launch at login")
    XCTAssertNotNil(checkbox)
    checkbox?.performClick(nil)
    XCTAssertNotNil(capturedValue)
}
```

Also extend the two helpers in the same file:

In `makeSnapshot(...)`, add a parameter (after `keepTranscriptsInClipboardHistory`):

```swift
        keepTranscriptsInClipboardHistory: Bool = false,
        launchAtLoginEnabled: Bool = false
```

and pass it as the **last** argument to the `Snapshot(...)` initializer:

```swift
            dictionaryLoadErrorDescription: dictionaryLoadErrorDescription,
            launchAtLoginEnabled: launchAtLoginEnabled
        )
```

In `makeActions(...)`, add a parameter (after `setKeepTranscriptsInClipboardHistory`):

```swift
        setKeepTranscriptsInClipboardHistory: @escaping (Bool) -> Void = { _ in },
        setLaunchAtLogin: @escaping (Bool) -> Void = { _ in },
```

and pass it into the `Actions(...)` initializer (after `setKeepTranscriptsInClipboardHistory`):

```swift
            setKeepTranscriptsInClipboardHistory: setKeepTranscriptsInClipboardHistory,
            setLaunchAtLogin: setLaunchAtLogin,
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PreferencesWindowControllerTests` (or `make test`)
Expected: FAIL to build / unresolved members (`setLaunchAtLogin`, `launchAtLoginEnabled`, `generalLaunchAtLoginEnabled`, no checkbox titled "Launch at login"). This confirms the wiring does not exist yet.

- [ ] **Step 3: Add the checkbox to `PreferencesGeneralView`**

In `Sources/AppUI/PreferencesGeneralView.swift`:

Add the property next to `clipboardHistoryCheckbox` (after line 14):

```swift
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
```

Add the stored closure next to `setKeepTranscriptsInClipboardHistory` (after line 18):

```swift
    private let setLaunchAtLogin: (Bool) -> Void
```

Add the init parameter (after the `setKeepTranscriptsInClipboardHistory` parameter, ~line 33):

```swift
        setKeepTranscriptsInClipboardHistory: @escaping (Bool) -> Void = { _ in },
        setLaunchAtLogin: @escaping (Bool) -> Void = { _ in }
```

Assign it in `init` (after the matching `self.setKeepTranscriptsInClipboardHistory` line, ~line 38):

```swift
        self.setLaunchAtLogin = setLaunchAtLogin
```

Wire the action and build the group. After the existing `clipboardGroup` block (after line 64), add:

```swift
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginCheckbox.font = .systemFont(ofSize: 13)

        let launchAtLoginSubtitle = NSTextField(labelWithString: "Start Scrawl automatically when you sign in.")
        launchAtLoginSubtitle.font = .systemFont(ofSize: 11)
        launchAtLoginSubtitle.textColor = .secondaryLabelColor

        let launchAtLoginGroup = NSStackView(views: [launchAtLoginCheckbox, launchAtLoginSubtitle])
        launchAtLoginGroup.orientation = .vertical
        launchAtLoginGroup.alignment = .leading
        launchAtLoginGroup.spacing = 3
```

Add `launchAtLoginGroup` to the page content, immediately after `clipboardGroup` (in the `content:` array, ~line 87):

```swift
                clipboardGroup,
                launchAtLoginGroup,
```

In `update(...)`, add the parameter (after `isCapturingHotkey: Bool`, ~line 102):

```swift
        isCapturingHotkey: Bool,
        launchAtLoginEnabled: Bool
```

and set the checkbox state at the end of `update` (after line 116):

```swift
        launchAtLoginCheckbox.state = launchAtLoginEnabled ? .on : .off
```

Add the accessor next to `isClipboardHistoryEnabled` (after line 140):

```swift
    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginCheckbox.state == .on
    }
```

Add the action handler next to `clipboardHistoryChanged` (after line 157):

```swift
    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
    }
```

- [ ] **Step 4: Thread through `PreferencesWindowController`**

In `Sources/AppUI/PreferencesWindowController.swift`:

Add to the `Actions` struct (after line 20, the `setKeepTranscriptsInClipboardHistory` field):

```swift
        let setLaunchAtLogin: (Bool) -> Void
```

Add to the `Snapshot` struct as the **last** field (after `dictionaryLoadErrorDescription`, line 44):

```swift
        let launchAtLoginEnabled: Bool
```

Pass it into the `PreferencesGeneralView` initializer (in `init`, after line 193):

```swift
            setKeepTranscriptsInClipboardHistory: actions.setKeepTranscriptsInClipboardHistory,
            setLaunchAtLogin: actions.setLaunchAtLogin
```

Pass it into `generalView.update` (in `update(snapshot:)`, after line 254):

```swift
            isCapturingHotkey: snapshot.isCapturingHotkey,
            launchAtLoginEnabled: snapshot.launchAtLoginEnabled
```

Add the accessor next to `generalIsClipboardHistoryEnabled` (after line 186):

```swift
    var generalLaunchAtLoginEnabled: Bool {
        generalView.isLaunchAtLoginEnabled
    }
```

- [ ] **Step 5: Wire `ScrawlApplication`**

In `Sources/AppUI/ScrawlApplication.swift`:

Add the import alongside the existing imports (after `import SettingsStore`, line 6):

```swift
import ServiceManagement
```

Add the stored login item. Place it with the other stored properties on `ScrawlApplication` (search for an existing `private let runtime` / similar stored property and add nearby):

```swift
    private let loginItem: LoginItemControlling = SMAppServiceLoginItem()
```

In `makePreferencesWindowController()`, add the action inside the `Actions(...)` initializer, immediately after the `setKeepTranscriptsInClipboardHistory:` closure:

```swift
                setLaunchAtLogin: { [weak self] enabled in
                    self?.setLaunchAtLogin(enabled)
                },
```

In `refreshPreferencesWindow()`, add the snapshot field as the **last** argument of the `Snapshot(...)` initializer (after `dictionaryLoadErrorDescription:`):

```swift
                dictionaryLoadErrorDescription: runtime.dictionaryStore.loadErrorDescription,
                launchAtLoginEnabled: loginItem.isEnabled
            )
```

Add the handler method and its alert helper. Place them near the other private settings handlers (e.g. after `mutateSettings` or alongside `setModelOffloadPolicy`):

```swift
    /// Toggles the macOS login item, then re-renders the checkbox from the live OS
    /// state so it can never drift. On failure or when macOS requires approval,
    /// guides the user to System Settings → General → Login Items.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            if enabled, !loginItem.isEnabled {
                presentLoginItemAlert(
                    message: "Approval needed for launch at login",
                    informative: "macOS needs you to allow Scrawl under System Settings → General → Login Items."
                )
            }
        } catch {
            presentLoginItemAlert(
                message: "Couldn't update launch at login",
                informative: "Scrawl couldn't change your login item. You can manage it under System Settings → General → Login Items."
            )
        }
        refreshPreferencesWindow()
    }

    private func presentLoginItemAlert(message: String, informative: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: "Open Login Items Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
```

- [ ] **Step 6: Run the new test to verify it passes**

Run: `swift test --filter PreferencesWindowControllerTests` (or `make test`)
Expected: `testGeneralLaunchAtLoginCheckboxReflectsStateAndDispatchesAction` PASSES.

- [ ] **Step 7: Run the full suite**

Run: `make test`
Expected: all pass (308 passing, 1 skipped). Pay attention to `testEverySettingsPageFitsAtMinimumWindowSize` — the General page gained one compact group. If it fails for General, the page overflows the minimum window; tighten the new group's spacing or fold the subtitle, then re-run. If it passes, no action needed.

- [ ] **Step 8: Run formatter and linter**

Run the repo's SwiftFormat and SwiftLint. Expected: clean (apply any formatting it produces and re-run the suite if it changed files).

- [ ] **Step 9: Commit**

```bash
git add Sources/AppUI/PreferencesGeneralView.swift Sources/AppUI/PreferencesWindowController.swift Sources/AppUI/ScrawlApplication.swift Tests/AppUITests/PreferencesWindowControllerTests.swift
git commit -m "feat: add Launch at login setting"
```

---

## Task 3: Manual verification in the installed app

`SMAppService.mainApp` needs a real, code-signed app bundle; `swift run` / `make run` does **not** register a login item. This task is the only way to verify the actual OS behavior. No code changes.

**Files:** none.

- [ ] **Step 1: Build and install the app bundle**

Run: `make install PREFIX=/Applications`
Expected: `Scrawl.app` installed to `/Applications`.

- [ ] **Step 2: Enable the checkbox**

Open `/Applications/Scrawl.app`, go to Settings → General, check **Launch at login**.
Expected: the checkbox stays checked. Verify in System Settings → General → Login Items that **Scrawl** is listed and enabled.

- [ ] **Step 3: Confirm it survives sign-out/in (or reboot)**

Log out and back in (or reboot).
Expected: Scrawl's menu-bar icon appears automatically after sign-in.

- [ ] **Step 4: Disable and confirm removal**

Uncheck **Launch at login** in Settings → General.
Expected: the checkbox stays unchecked and Scrawl disappears from System Settings → Login Items.

- [ ] **Step 5: Confirm no-drift behavior**

Re-enable in Scrawl, then remove Scrawl from System Settings → Login Items directly. Reopen Scrawl's Settings → General.
Expected: the checkbox is unchecked, reflecting the OS state (no drift).

If any step fails, stop and debug before proceeding to docs.

---

## Task 4: Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the feature bullet**

In `README.md`, in the `## Features` list (lines 58-63), add a bullet after the "Local history" line, matching the existing terse voice (bold lead + period, no em-dashes):

```markdown
- **Launch at login.** Start Scrawl in the menu bar when you sign in, from Settings → General.
```

- [ ] **Step 2: Commit**

`docs/` is locally git-excluded only for generated assets; `README.md` is tracked normally, so a plain add works.

```bash
git add README.md
git commit -m "docs: note launch-at-login in README features"
```

- [ ] **Step 3: Update the PR #10 description (with the user's go-ahead)**

The feature commits push to the `v0.0.10` branch, which already backs PR #10. Pushing to the feature branch and editing the PR body are staging actions — do them only once the user confirms (per the repo's "confirm before merge & release" rule, staging is allowed but confirm the push).

Add a Features line to the PR body via `gh pr edit 10` (or the GitHub UI), in the existing voice:

```
- **Launch at login** — opt-in checkbox in Settings → General that starts Scrawl at sign-in via SMAppService.
```

---

## Self-Review

**Spec coverage:**
- Mechanism (`SMAppService.mainApp` register/unregister/status) → Task 1.
- Source of truth, no `AppSettings` field → enforced in Global Constraints; snapshot sources `loginItem.isEnabled` (Task 2, Step 5); verified Task 3 Step 5.
- `LoginItem.swift` protocol + concrete seam → Task 1.
- `PreferencesGeneralView` checkbox + subtitle + closure + update param → Task 2, Step 3.
- `Actions` / `Snapshot` / controller pass-through + accessor → Task 2, Steps 4.
- `ScrawlApplication` closure + error/approval handling + snapshot fill → Task 2, Step 5.
- Error handling (throw → alert; `.requiresApproval` → guidance; deep-link to Login Items) → Task 2, Step 5 (`presentLoginItemAlert`, `SMAppService.openSystemSettingsLoginItems()`).
- Placement (General, below clipboard group) + exact copy → Task 2, Step 3 + Global Constraints.
- Testing (view reflects state + dispatches; revert = re-render from truth) → Task 2, Steps 1/6; `SMAppServiceLoginItem` manual → Task 3.
- Dev limitation (needs real bundle) → Task 3 preamble.
- Docs (README + PR body) → Task 4.

**Placeholder scan:** none — every code step shows complete code.

**Type consistency:** `LoginItemControlling.isEnabled` / `setEnabled(_:)`, `setLaunchAtLogin`, `launchAtLoginEnabled`, `isLaunchAtLoginEnabled`, `generalLaunchAtLoginEnabled`, `presentLoginItemAlert(message:informative:)` are used identically everywhere they appear. `Snapshot.launchAtLoginEnabled` is declared last and constructed last at both sites (`refreshPreferencesWindow`, `makeSnapshot`).
