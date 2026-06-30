# Preferences Graphite Workbench Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved Graphite Workbench Preferences redesign with native AppKit controls, restrained SF Symbols, split model management, History-to-Dictionary preferred-term capture, and snapshot verification.

**Architecture:** Keep the existing AppKit view-per-page structure and add small shared helpers in `PreferencesPageSupport` only where they reduce repeated layout code. The redesign is implemented incrementally: shell/navigation first, then Models, History, Dictionary, and snapshots. Existing model, transcript, and dictionary storage behavior remains unchanged.

**Tech Stack:** Swift, AppKit, XCTest, existing `SettingsStore`, `TranscriptHistoryStore`, and `DictionaryStore` modules.

## Global Constraints

- Use native SF Symbols through AppKit only.
- Treat `docs/mockups/preferences-graphite-workbench-source-list.png` as a flow reference, not an exact visual target.
- Do not use generated line icons, custom cube icons, or decorative per-row model icons.
- Preferences sections must be `General`, `Models`, `Input`, `History`, `Dictionary`, `About`.
- `General` opens first.
- Models must not include search, visible table headers, cube icons, or row kebab menus.
- Models rows use `info.circle` for details popovers.
- History uses `Add Term...`, not `Correct...`.
- Dictionary is a preferred-terms list, not a replacement-rule editor.
- Workbench bottom action bars are limited to Models, History, and Dictionary.
- Verify visual changes with rendered AppKit snapshots.

---

## File Structure

- Modify `Sources/AppUI/PreferencesWindowController.swift`: rename section taxonomy, wire General `Change...`, install graphite sidebar treatment, expose small test accessors.
- Modify `Sources/AppUI/PreferencesGeneralView.swift`: add current-model `Change...` action while preserving existing settings rows.
- Modify `Sources/AppUI/PreferencesKeyboardView.swift`: retitle the page to Input and keep hotkey behavior.
- Modify `Sources/AppUI/PreferencesPageSupport.swift`: add pinned bottom action row and compact section helpers used by workbench pages.
- Modify `Sources/AppUI/PreferencesModelsView.swift`: replace one stretched list with Installed and Available sections, native rows, `info.circle`, progress bar, and pinned actions.
- Modify `Sources/AppUI/PreferencesHistoryView.swift`: add `Add Term...` bottom action and preferred-term popover.
- Modify `Sources/AppUI/PreferencesDictionaryView.swift`: rename visible copy to Dictionary and use pinned workbench actions.
- Modify `Tests/AppUITests/PreferencesWindowControllerTests.swift`: update navigation/copy tests and add behavior tests for new shell and Add Term.
- Modify `Tests/AppUITests/PreferencesModelsViewTests.swift`: replace old single-list layout assertions with split-section assertions.
- Modify `Tests/AppUITests/PreferencesModelsViewSnapshotTests.swift`: update snapshot writer for new Models layout.
- Create `Tests/AppUITests/PreferencesWindowSnapshotTests.swift`: opt-in PNG snapshots for full Preferences shell pages.
- Modify `Makefile`: add `snapshots-preferences` target next to `snapshots-models`.

---

### Task 1: Navigation, Input Rename, Dictionary Rename, And General Change Action

**Files:**
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Sources/AppUI/PreferencesGeneralView.swift`
- Modify: `Sources/AppUI/PreferencesKeyboardView.swift`
- Modify: `Sources/AppUI/PreferencesDictionaryView.swift`
- Test: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

**Interfaces:**
- Produces: `PreferencesWindowController.Section.input`
- Produces: `PreferencesGeneralView.changeModel: () -> Void`
- Consumes: existing `PreferencesWindowController.selectSection(_:)`

- [ ] **Step 1: Write failing tests**

Add/update tests:

```swift
@MainActor
func testSidebarContainsGraphiteWorkbenchSections() {
    XCTAssertEqual(
        PreferencesWindowController.Section.allCases.map(\.title),
        ["General", "Models", "Input", "History", "Dictionary", "About"]
    )
}

@MainActor
func testGeneralChangeModelButtonSelectsModels() throws {
    let controller = PreferencesWindowController(actions: makeActions())
    let contentView = try XCTUnwrap(controller.window?.contentView)

    XCTAssertEqual(controller.visibleSection, .general)
    try XCTUnwrap(contentView.button(titled: "Change...")).performClick(nil)

    XCTAssertEqual(controller.visibleSection, .models)
}

@MainActor
func testInputAndDictionaryVisibleCopyUseNewNames() throws {
    let controller = PreferencesWindowController(actions: makeActions())
    let contentView = try XCTUnwrap(controller.window?.contentView)

    controller.selectSection(.input)
    XCTAssertNotNil(contentView.textField(withValue: "Input"))

    controller.selectSection(.dictionary)
    XCTAssertNotNil(contentView.textField(withValue: "Dictionary"))
    XCTAssertNil(contentView.textField(withValue: "Vocabulary"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: failures because `.input` does not exist, section titles still include `Keyboard` and `Vocabulary`, `Change...` does not exist, and Dictionary page title is still `Vocabulary`.

- [ ] **Step 3: Implement minimal code**

Implementation details:

- Rename `Section.keyboard` to `Section.input`.
- Change section title from `Keyboard` to `Input`.
- Keep `symbolName` as `keyboard`.
- Keep `PreferencesKeyboardView` as the class name for now, but change page title to `Input`.
- Add `var changeModel: () -> Void = {}` and a `Change...` button to `PreferencesGeneralView`.
- After `super.init(window:)`, set `generalView.changeModel = { [weak self] in self?.selectSection(.models) }` before assigning `window.contentView`.
- Change Dictionary visible strings from Vocabulary to Dictionary: page title, search placeholder, unavailable state title, reset button.
- Update tests that select `.keyboard` to select `.input`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: all `PreferencesWindowControllerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppUI/PreferencesWindowController.swift Sources/AppUI/PreferencesGeneralView.swift Sources/AppUI/PreferencesKeyboardView.swift Sources/AppUI/PreferencesDictionaryView.swift Tests/AppUITests/PreferencesWindowControllerTests.swift
git commit -m "Redesign preferences navigation shell"
```

---

### Task 2: Shared Workbench Layout Helpers And Graphite Sidebar

**Files:**
- Modify: `Sources/AppUI/PreferencesPageSupport.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Test: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

**Interfaces:**
- Produces: `PreferencesPageSupport.makePinnedActionBar(leading:trailing:) -> NSView`
- Produces: `PreferencesPageSupport.makeSectionLabel(_:) -> NSTextField`
- Produces: `PreferencesWindowController.usesGraphiteSidebar: Bool`
- Produces: `PreferencesWindowController.sidebarSymbolNames: [String]`

- [ ] **Step 1: Write failing tests**

Add tests:

```swift
@MainActor
func testSidebarUsesOnlyApprovedSFSymbolNames() {
    let controller = PreferencesWindowController(actions: makeActions())
    XCTAssertEqual(
        controller.sidebarSymbolNames,
        ["gearshape", "cpu", "keyboard", "clock.arrow.circlepath", "text.book.closed", "info.circle"]
    )
}

@MainActor
func testSidebarUsesGraphiteTreatment() {
    let controller = PreferencesWindowController(actions: makeActions())
    XCTAssertTrue(controller.usesGraphiteSidebar)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: failures because the new accessors and sidebar treatment do not exist.

- [ ] **Step 3: Implement minimal code**

Implementation details:

- Add `PreferencesSidebarBackgroundView: NSView` local to `PreferencesWindowController.swift`, with a dark graphite layer color.
- Set `sidebarTable.selectionHighlightStyle = .regular`, `rowHeight = 34`, and `usesAlternatingRowBackgroundColors = false`.
- Use existing SF Symbol names from `Section.symbolName`.
- Expose `sidebarSymbolNames` as `Section.allCases.map(\.symbolName)`.
- Expose `usesGraphiteSidebar` by checking the sidebar root view type or identifier.
- Add `PreferencesPageSupport.makePinnedActionBar(leading:trailing:)`.
- Add `PreferencesPageSupport.makeSectionLabel(_:)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppUI/PreferencesPageSupport.swift Sources/AppUI/PreferencesWindowController.swift Tests/AppUITests/PreferencesWindowControllerTests.swift
git commit -m "Add graphite preferences shell helpers"
```

---

### Task 3: Models Workbench Split Sections

**Files:**
- Modify: `Sources/AppUI/PreferencesModelsView.swift`
- Modify: `Tests/AppUITests/PreferencesModelsViewTests.swift`
- Modify: `Tests/AppUITests/PreferencesWindowControllerTests.swift`
- Modify: `Tests/AppUITests/PreferencesModelsViewSnapshotTests.swift`

**Interfaces:**
- Produces: `PreferencesModelsView.visibleInstalledSectionTitle: String?`
- Produces: `PreferencesModelsView.visibleAvailableSectionTitle: String?`
- Produces: `PreferencesModelsView.visibleModelSearchFieldCount: Int`
- Produces: `PreferencesModelsView.visibleModelInfoButtonCount: Int`
- Produces: `PreferencesModelsView.visiblePinnedActionBarMinY: CGFloat?`

- [ ] **Step 1: Write failing tests**

Add/update tests:

```swift
@MainActor
func testModelsSplitInstalledAndAvailableSections() throws {
    let view = PreferencesModelsView(
        selectModel: { _ in },
        downloadModel: { _ in },
        deleteSelectedModel: {},
        cancelDownload: {},
        addModel: {},
        revealModelsFolder: {},
        openModelSource: {}
    )
    view.frame = NSRect(x: 0, y: 0, width: 560, height: 360)
    view.update(rows: [
        modelRow(id: "parakeet-v3", installed: true, selected: true),
        modelRow(id: "ggml-small.en", installed: true, selected: false),
        modelRow(id: "ggml-medium", installed: false, selected: false),
    ], downloadableModels: [], isDownloadInProgress: false)
    view.layoutSubtreeIfNeeded()

    XCTAssertEqual(view.visibleInstalledSectionTitle, "Installed Models")
    XCTAssertEqual(view.visibleAvailableSectionTitle, "Available Downloads")
    XCTAssertEqual(view.visibleModelSearchFieldCount, 0)
    XCTAssertEqual(view.visibleModelInfoButtonCount, 3)
}
```

Update old tests so they no longer require one single list container or `Find Models`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesModelsViewTests`

Expected: failures because split sections, info buttons, and pinned action bar are not implemented.

- [ ] **Step 3: Implement minimal code**

Implementation details:

- Replace one `modelsStack` list with a page-level vertical content stack containing section labels and grouped section stacks.
- Partition rows with `rows.filter(\.isInstalled)` and `rows.filter { !$0.isInstalled }`.
- Remove `findModelsButton` from visible layout.
- Preserve `openModelSource` in the initializer for compatibility, but do not show the old `Find Models` control.
- Add `info.circle` borderless buttons to rows with tooltips and fixed width.
- Add a slim determinate `NSProgressIndicator` when `row.isDownloading` and `downloadProgressText` contains a percent.
- Keep selected/current rows action-free: selected rows show checkmark instead of `Use`.
- Use `PreferencesPageSupport.makePinnedActionBar` for bottom controls.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesModelsViewTests`

Expected: all Models view tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppUI/PreferencesModelsView.swift Tests/AppUITests/PreferencesModelsViewTests.swift Tests/AppUITests/PreferencesWindowControllerTests.swift Tests/AppUITests/PreferencesModelsViewSnapshotTests.swift
git commit -m "Redesign models preferences workbench"
```

---

### Task 4: History Add Term Workflow

**Files:**
- Modify: `Sources/AppUI/PreferencesHistoryView.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Test: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

**Interfaces:**
- Modifies: `PreferencesHistoryView.Actions` to include `addTerm: (String, @escaping (Result<Void, Error>) -> Void) -> Void`
- Produces: `PreferencesWindowController.setHistoryPreferredTermDraft(_:)`
- Produces: `PreferencesWindowController.saveHistoryPreferredTermDraft()`

- [ ] **Step 1: Write failing tests**

Add test:

```swift
@MainActor
func testHistoryAddTermPopoverSavesPreferredTerm() throws {
    let record = TranscriptRecord(id: UUID(), createdAt: .now, text: "Anduril was mentioned")
    var savedValue: String?
    let controller = PreferencesWindowController(actions: makeActions(
        saveDictionaryEntry: { _, _, correct, completion in
            savedValue = correct
            completion(.success(()))
        }
    ))
    controller.update(snapshot: makeSnapshot(records: [record]))
    controller.selectSection(.history)
    let contentView = try XCTUnwrap(controller.window?.contentView)

    try XCTUnwrap(contentView.button(titled: "Add Term...")).performClick(nil)
    controller.setHistoryPreferredTermDraft("Anduril")
    controller.saveHistoryPreferredTermDraft()

    XCTAssertEqual(savedValue, "Anduril")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesWindowControllerTests/testHistoryAddTermPopoverSavesPreferredTerm`

Expected: failure because `Add Term...` and the test helpers do not exist.

- [ ] **Step 3: Implement minimal code**

Implementation details:

- Add `addTermButton = NSButton(title: "Add Term...", ...)` to the History bottom action bar.
- Add `addTerm` to `PreferencesHistoryView.Actions`.
- In `PreferencesWindowController`, pass `{ term, completion in actions.saveDictionaryEntry(nil, term, term, completion) }`.
- Show an `NSPopover` anchored to `Add Term...` with one editable field placeholder/value `Preferred term`, plus `Save` and `Cancel`.
- Keep the popover field empty for v1.
- Add test-only accessors/methods on `PreferencesHistoryView` and forward through `PreferencesWindowController`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: History tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppUI/PreferencesHistoryView.swift Sources/AppUI/PreferencesWindowController.swift Tests/AppUITests/PreferencesWindowControllerTests.swift
git commit -m "Add history preferred term workflow"
```

---

### Task 5: Dictionary Workbench Polish

**Files:**
- Modify: `Sources/AppUI/PreferencesDictionaryView.swift`
- Modify: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

**Interfaces:**
- Produces: visible title `Dictionary`
- Produces: visible reset button `Reset Dictionary`
- Produces: search placeholder `Search dictionary`

- [ ] **Step 1: Write failing tests**

Update tests:

```swift
@MainActor
func testDictionaryPageShowsUnavailableStateAndDispatchesRecovery() throws {
    var didRecover = false
    let controller = PreferencesWindowController(actions: makeActions(
        recoverDictionary: { completion in
            didRecover = true
            completion(.success(()))
        }
    ))

    controller.update(snapshot: makeSnapshot(dictionaryLoadErrorDescription: "corrupt"))
    controller.selectSection(.dictionary)
    let contentView = try XCTUnwrap(controller.window?.contentView)

    XCTAssertEqual(controller.dictionaryState, .unavailable)
    try XCTUnwrap(contentView.button(titled: "Reset Dictionary")).performClick(nil)
    XCTAssertTrue(didRecover)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: failures until visible copy is renamed and action layout updated.

- [ ] **Step 3: Implement minimal code**

Implementation details:

- Change page title to `Dictionary`.
- Change search placeholder to `Search dictionary`.
- Change reset button to `Reset Dictionary`.
- Use `PreferencesPageSupport.makePinnedActionBar(leading: [editButton], trailing: [deleteButton])` under the workspace.
- Keep add row and search field native and compact.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AppUI/PreferencesDictionaryView.swift Tests/AppUITests/PreferencesWindowControllerTests.swift
git commit -m "Polish dictionary preferences page"
```

---

### Task 6: Full Preferences Snapshots And Final Verification

**Files:**
- Create: `Tests/AppUITests/PreferencesWindowSnapshotTests.swift`
- Modify: `Tests/AppUITests/PreferencesModelsViewSnapshotTests.swift`
- Modify: `Makefile`

**Interfaces:**
- Produces: `SCRAWL_PREFERENCES_SNAPSHOT_DIR` opt-in snapshot test.
- Produces: `make snapshots-preferences`.

- [ ] **Step 1: Write failing snapshot test**

Create `PreferencesWindowSnapshotTests` that writes:

- `preferences-general.png`
- `preferences-models.png`
- `preferences-history.png`
- `preferences-dictionary.png`
- `preferences-minimum-width.png`

Skip unless `SCRAWL_PREFERENCES_SNAPSHOT_DIR` is set.

- [ ] **Step 2: Run test to verify it fails or skips correctly**

Run without env:

`swift test --filter PreferencesWindowSnapshotTests`

Expected: skipped test.

Run with env:

`SCRAWL_PREFERENCES_SNAPSHOT_DIR=/tmp/scrawl-preferences swift test --filter PreferencesWindowSnapshotTests`

Expected before implementation completion: missing writer or snapshot failures.

- [ ] **Step 3: Implement snapshot writer and Makefile target**

Add:

```make
SNAPSHOT_PREFERENCES_DIR ?= /tmp/scrawl-preferences

snapshots-preferences:
	rm -rf "$(SNAPSHOT_PREFERENCES_DIR)"
	SCRAWL_PREFERENCES_SNAPSHOT_DIR="$(SNAPSHOT_PREFERENCES_DIR)" swift test --filter PreferencesWindowSnapshotTests
	open "$(SNAPSHOT_PREFERENCES_DIR)"
```

- [ ] **Step 4: Run full focused verification**

Run:

```bash
swift test --filter PreferencesWindowControllerTests
swift test --filter PreferencesModelsViewTests
swift test --filter PreferencesModelsViewSnapshotTests
swift test --filter PreferencesWindowSnapshotTests
make snapshots-preferences
```

Expected: tests pass or snapshot tests skip without env; `make snapshots-preferences` writes PNGs and opens `/tmp/scrawl-preferences`.

- [ ] **Step 5: Manual visual review and final commit**

Open generated PNGs and check:

- graphite sidebar is quiet, not SaaS-heavy
- only SF Symbols appear
- no cube row icons
- Models has split Installed and Available sections
- no Models search field
- History action bar fits
- Dictionary copy is visible
- minimum-width layout does not overlap

Commit:

```bash
git add Tests/AppUITests/PreferencesWindowSnapshotTests.swift Tests/AppUITests/PreferencesModelsViewSnapshotTests.swift Makefile
git commit -m "Add preferences redesign snapshots"
```

---

## Self-Review

Spec coverage:

- Shell/navigation: Tasks 1 and 2.
- Graphite sidebar and icon constraints: Task 2.
- General landing and Change action: Task 1.
- Models split workbench: Task 3.
- Input rename: Task 1.
- History Add Term workflow: Task 4.
- Dictionary rename and preferred-term scope: Task 5.
- Snapshot verification: Task 6.

Placeholder scan:

- No placeholder markers or unspecified future work appears in task steps.

Type consistency:

- Section rename uses `.input` consistently.
- History term saving routes through existing `saveDictionaryEntry(nil, term, term, completion)`.
- Snapshot env names are distinct: `SCRAWL_SNAPSHOT_DIR` remains Models-only, `SCRAWL_PREFERENCES_SNAPSHOT_DIR` is full-window.
