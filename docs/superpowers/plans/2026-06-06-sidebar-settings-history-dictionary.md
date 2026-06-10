# Sidebar Settings, History, and Dictionary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Scrawl's segmented preferences form with a compact native sidebar window and add persistent, privacy-controlled transcript History and a complete Dictionary editor.

**Architecture:** Add a standalone `TranscriptHistoryStore` module for persistent records, extend settings and dictionary storage with the smallest required APIs, and keep filtering/state transformation in testable AppUI helpers. Split the AppKit window into a thin sidebar controller plus focused page views; `StatusBarAppDelegate` remains the coordinator that mutates stores and refreshes the window and menubar.

**Tech Stack:** Swift 5.10, AppKit, Foundation, Swift Package Manager, XCTest

---

## File Structure

### New Files

- `Sources/TranscriptHistoryStore/TranscriptHistoryStore.swift`
  Defines `TranscriptRecord`, `TranscriptHistoryStoring`, and in-memory/JSON implementations.
- `Tests/TranscriptHistoryStoreTests/TranscriptHistoryStoreTests.swift`
  Verifies ordering, limit, persistence, deletion, and clearing.
- `Sources/AppUI/TranscriptHistoryCoordinator.swift`
  Applies the enabled setting when adding records and performs clear-before-disable.
- `Sources/AppUI/PreferencesContentState.swift`
  Pure filtering and selection helpers for History and Dictionary.
- `Sources/AppUI/PreferencesPageSupport.swift`
  Shared AppKit page title, setting row, and button helpers.
- `Sources/AppUI/PreferencesGeneralView.swift`
  General readiness/model/hotkey/permission summary.
- `Sources/AppUI/PreferencesModelsView.swift`
  Existing model management behavior.
- `Sources/AppUI/PreferencesKeyboardView.swift`
  Hotkey capture and gesture explanation.
- `Sources/AppUI/PreferencesHistoryView.swift`
  History split view, search, actions, text selection, and dictionary popover.
- `Sources/AppUI/PreferencesDictionaryView.swift`
  Searchable dictionary table and replacement editor.
- `Sources/AppUI/PreferencesAboutView.swift`
  Version, privacy statement, and project link.
- `Tests/AppUITests/TranscriptHistoryCoordinatorTests.swift`
  Verifies enabled/disabled record behavior and clear-on-disable.
- `Tests/AppUITests/PreferencesContentStateTests.swift`
  Verifies History and Dictionary filtering and selection fallback.

### Modified Files

- `Package.swift`
  Registers the history module and test target and makes it available to AppUI.
- `Sources/SettingsStore/SettingsStore.swift`
  Adds the enabled-by-default history preference.
- `Tests/SettingsStoreTests/AppSettingsDecodingTests.swift`
  Verifies default and migration behavior.
- `Sources/DictionaryStore/DictionaryStore.swift`
  Adds explicit edit/delete helpers used by the UI.
- `Tests/DictionaryStoreTests/DictionaryReplacerTests.swift`
  Verifies dictionary mutation behavior.
- `Sources/AppUI/AppRuntime.swift`
  Wires the live JSON history store.
- `Sources/AppUI/PreferencesWindowController.swift`
  Becomes the compact sidebar shell and routes snapshots/actions to page views.
- `Sources/AppUI/ScrawlApplication.swift`
  Replaces in-memory history with the store, coordinates page actions, and refreshes menus.
- `README.md`
  Documents local persistent history and the privacy control.

---

### Task 1: Add the Transcript History Storage Module

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TranscriptHistoryStore/TranscriptHistoryStore.swift`
- Create: `Tests/TranscriptHistoryStoreTests/TranscriptHistoryStoreTests.swift`

- [ ] **Step 1: Register the module and write failing storage tests**

Add `TranscriptHistoryStore` as a library product and target, add it to `AppUI` dependencies, add `DictionaryStore` and `TranscriptHistoryStore` as direct `AppUITests` dependencies, and add `TranscriptHistoryStoreTests`.

Write tests covering newest-first insertion, the 100-record cap, deletion, clearing, and JSON reload:

```swift
import TranscriptHistoryStore
import XCTest

final class TranscriptHistoryStoreTests: XCTestCase {
    func testAddStoresNewestFirstAndCapsAtLimit() throws {
        let store = InMemoryTranscriptHistoryStore(limit: 3)
        for index in 0..<4 {
            try store.add(TranscriptRecord(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                text: "\(index)"
            ))
        }
        XCTAssertEqual(store.records().map(\.text), ["3", "2", "1"])
    }

    func testDeleteAndClearRemoveRecords() throws {
        let first = TranscriptRecord(id: UUID(), createdAt: .distantPast, text: "first")
        let second = TranscriptRecord(id: UUID(), createdAt: .distantFuture, text: "second")
        let store = InMemoryTranscriptHistoryStore(records: [first, second])

        try store.delete(ids: [first.id])
        XCTAssertEqual(store.records(), [second])

        try store.clear()
        XCTAssertTrue(store.records().isEmpty)
    }

    func testJSONStorePersistsRecordsAcrossInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "history.json")
        let record = TranscriptRecord(id: UUID(), createdAt: Date(timeIntervalSince1970: 123), text: "hello")

        try JSONTranscriptHistoryStore(fileURL: fileURL).add(record)

        XCTAssertEqual(JSONTranscriptHistoryStore(fileURL: fileURL).records(), [record])
    }

    func testJSONDeleteAndClearPersistAcrossInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let fileURL = directory.appending(path: "history.json")
        let first = TranscriptRecord(id: UUID(), createdAt: .distantPast, text: "first")
        let second = TranscriptRecord(id: UUID(), createdAt: .distantFuture, text: "second")
        let store = JSONTranscriptHistoryStore(fileURL: fileURL)
        try store.add(first)
        try store.add(second)

        try store.delete(ids: Set([first.id]))
        XCTAssertEqual(JSONTranscriptHistoryStore(fileURL: fileURL).records(), [second])

        try store.clear()
        XCTAssertTrue(JSONTranscriptHistoryStore(fileURL: fileURL).records().isEmpty)
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
swift test --filter TranscriptHistoryStoreTests
```

Expected: build failure because `TranscriptHistoryStore` and its types do not exist.

- [ ] **Step 3: Implement the history store**

Implement this public surface, using an `NSLock`, atomic JSON writes, newest-first sorting, and a default limit of 100:

```swift
public struct TranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String

    public init(id: UUID, createdAt: Date, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
    }
}

public protocol TranscriptHistoryStoring: Sendable {
    func records() -> [TranscriptRecord]
    func add(_ record: TranscriptRecord) throws
    func delete(ids: Set<UUID>) throws
    func clear() throws
}

public final class InMemoryTranscriptHistoryStore: TranscriptHistoryStoring, @unchecked Sendable {
    public init(records: [TranscriptRecord] = [], limit: Int = 100)
}

public final class JSONTranscriptHistoryStore: TranscriptHistoryStoring, @unchecked Sendable {
    public init(fileURL: URL, limit: Int = 100)
}
```

For both implementations, normalize records with:

```swift
Array(records
    .sorted { $0.createdAt > $1.createdAt }
    .prefix(limit))
```

For JSON mutation, compute the new array, write it successfully, then replace the cache so failed writes do not falsely update visible state.

- [ ] **Step 4: Run the storage tests**

Run:

```bash
swift test --filter TranscriptHistoryStoreTests
```

Expected: all `TranscriptHistoryStoreTests` pass.

- [ ] **Step 5: Commit the storage module**

```bash
git add Package.swift Sources/TranscriptHistoryStore Tests/TranscriptHistoryStoreTests
git commit -m "Add persistent transcript history store"
```

---

### Task 2: Add the History Privacy Setting and Coordinator

**Files:**
- Modify: `Sources/SettingsStore/SettingsStore.swift`
- Modify: `Tests/SettingsStoreTests/AppSettingsDecodingTests.swift`
- Create: `Sources/AppUI/TranscriptHistoryCoordinator.swift`
- Create: `Tests/AppUITests/TranscriptHistoryCoordinatorTests.swift`

- [ ] **Step 1: Write failing settings migration tests**

Add:

```swift
func testTranscriptHistoryIsEnabledByDefault() {
    XCTAssertTrue(AppSettings().isTranscriptHistoryEnabled)
}

func testLegacySettingsDecodeWithTranscriptHistoryEnabled() throws {
    let data = try XCTUnwrap("""
    {"defaultModelID":"tiny.en","selectedModelID":"tiny.en","language":"en"}
    """.data(using: .utf8))

    XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).isTranscriptHistoryEnabled)
}
```

- [ ] **Step 2: Run settings tests and verify they fail**

Run:

```bash
swift test --filter AppSettingsDecodingTests
```

Expected: build failure because `isTranscriptHistoryEnabled` does not exist.

- [ ] **Step 3: Add the setting with migration-safe coding**

Add the property and initializer argument:

```swift
public var isTranscriptHistoryEnabled: Bool

public init(
    defaultModelID: String = "ggml-small.en",
    selectedModelID: String = "ggml-small.en",
    language: String = "en",
    hotkey: HotkeySetting = HotkeySetting(),
    modelsDirectoryPath: String? = nil,
    isTranscriptHistoryEnabled: Bool = true
)
```

Add the coding key, decode with `?? true`, and encode the value.

- [ ] **Step 4: Write failing coordinator tests**

Use an isolated `UserDefaults` suite and `InMemoryTranscriptHistoryStore`:

```swift
@testable import AppUI
import SettingsStore
import TranscriptHistoryStore
import XCTest

final class TranscriptHistoryCoordinatorTests: XCTestCase {
    func testAddDoesNothingWhenHistoryIsDisabled() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settingsStore = SettingsStore(defaults: defaults)
        var settings = AppSettings()
        settings.isTranscriptHistoryEnabled = false
        try settingsStore.save(settings)
        let historyStore = InMemoryTranscriptHistoryStore()
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)

        try coordinator.add(text: "private", createdAt: .now)

        XCTAssertTrue(historyStore.records().isEmpty)
    }

    func testDisableClearsRecordsBeforeSavingDisabledSetting() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settingsStore = SettingsStore(defaults: defaults)
        let historyStore = InMemoryTranscriptHistoryStore(records: [
            TranscriptRecord(id: UUID(), createdAt: .now, text: "delete me")
        ])
        let coordinator = TranscriptHistoryCoordinator(settingsStore: settingsStore, historyStore: historyStore)

        try coordinator.setEnabled(false)

        XCTAssertTrue(historyStore.records().isEmpty)
        XCTAssertFalse(settingsStore.load().isTranscriptHistoryEnabled)
    }

    func testDisableLeavesSettingEnabledWhenClearFails() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settingsStore = SettingsStore(defaults: defaults)
        let coordinator = TranscriptHistoryCoordinator(
            settingsStore: settingsStore,
            historyStore: FailingClearHistoryStore()
        )

        XCTAssertThrowsError(try coordinator.setEnabled(false))
        XCTAssertTrue(settingsStore.load().isTranscriptHistoryEnabled)
    }
}
```

Define this test stub in the same file:

```swift
private struct FailingClearHistoryStore: TranscriptHistoryStoring {
    enum Failure: Error { case clear }

    func records() -> [TranscriptRecord] { [] }
    func add(_ record: TranscriptRecord) throws {}
    func delete(ids: Set<UUID>) throws {}
    func clear() throws { throw Failure.clear }
}
```

- [ ] **Step 5: Implement the coordinator**

Create:

```swift
import Foundation
import SettingsStore
import TranscriptHistoryStore

struct TranscriptHistoryCoordinator {
    let settingsStore: SettingsStore
    let historyStore: any TranscriptHistoryStoring

    func add(text: String, createdAt: Date = .now) throws {
        guard settingsStore.load().isTranscriptHistoryEnabled else { return }
        try historyStore.add(TranscriptRecord(id: UUID(), createdAt: createdAt, text: text))
    }

    func setEnabled(_ enabled: Bool) throws {
        var settings = settingsStore.load()
        if !enabled {
            try historyStore.clear()
        }
        settings.isTranscriptHistoryEnabled = enabled
        try settingsStore.save(settings)
    }
}
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
swift test --filter AppSettingsDecodingTests
swift test --filter TranscriptHistoryCoordinatorTests
```

Expected: both suites pass.

- [ ] **Step 7: Commit privacy behavior**

```bash
git add Sources/SettingsStore Tests/SettingsStoreTests Sources/AppUI/TranscriptHistoryCoordinator.swift Tests/AppUITests/TranscriptHistoryCoordinatorTests.swift
git commit -m "Add transcript history privacy setting"
```

---

### Task 3: Add Explicit Dictionary Mutation APIs

**Files:**
- Modify: `Sources/DictionaryStore/DictionaryStore.swift`
- Modify: `Tests/DictionaryStoreTests/DictionaryReplacerTests.swift`

- [ ] **Step 1: Write failing mutation tests**

Add:

```swift
func testDeleteRemovesCaseInsensitiveKeys() throws {
    let store = InMemoryDictionaryStore(entries: [
        DictionaryEntry(wrong: "kubernetes", correct: "Kubernetes"),
        DictionaryEntry(wrong: "postgres", correct: "Postgres")
    ])

    try store.delete(wrongValues: Set(["KUBERNETES"]))

    XCTAssertEqual(store.entries(), [DictionaryEntry(wrong: "postgres", correct: "Postgres")])
}

func testAddOrReplaceRejectsBlankValues() throws {
    let store = InMemoryDictionaryStore()
    try store.addOrReplace(wrong: " ", correct: "value")
    XCTAssertTrue(store.entries().isEmpty)
}

func testReplaceRemovesOriginalKeyWhenHeardTextChanges() throws {
    let store = InMemoryDictionaryStore(entries: [
        DictionaryEntry(wrong: "post grass", correct: "Postgres")
    ])

    try store.replace(originalWrong: "post grass", wrong: "post gres", correct: "Postgres")

    XCTAssertEqual(store.entries(), [DictionaryEntry(wrong: "post gres", correct: "Postgres")])
}
```

- [ ] **Step 2: Run dictionary tests and verify failure**

Run:

```bash
swift test --filter DictionaryReplacerTests
```

Expected: build failure because `delete(wrongValues:)` and `replace(originalWrong:wrong:correct:)` do not exist.

- [ ] **Step 3: Implement explicit deletion**

Add to the protocol extension:

```swift
func delete(wrongValues: Set<String>) throws {
    let normalized = Set(wrongValues.map { $0.lowercased() })
    try save(entries().filter { !normalized.contains($0.wrong.lowercased()) })
}

func replace(originalWrong: String, wrong: String, correct: String) throws {
    let trimmedWrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCorrect = correct.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedWrong.isEmpty, !trimmedCorrect.isEmpty else { return }

    var updated = entries().filter {
        $0.wrong.caseInsensitiveCompare(originalWrong) != .orderedSame
            && $0.wrong.caseInsensitiveCompare(trimmedWrong) != .orderedSame
    }
    updated.append(DictionaryEntry(wrong: trimmedWrong, correct: trimmedCorrect))
    try save(updated)
}
```

Use `addOrReplace` for new entries from History and the Add sheet. Use `replace` for Dictionary edits so changing the heard-text key does not leave the original entry behind.

- [ ] **Step 4: Run dictionary tests**

Run:

```bash
swift test --filter DictionaryReplacerTests
```

Expected: all dictionary tests pass.

- [ ] **Step 5: Commit dictionary mutations**

```bash
git add Sources/DictionaryStore/DictionaryStore.swift Tests/DictionaryStoreTests/DictionaryReplacerTests.swift
git commit -m "Add dictionary deletion API"
```

---

### Task 4: Add Testable Preferences Content State

**Files:**
- Create: `Sources/AppUI/PreferencesContentState.swift`
- Create: `Tests/AppUITests/PreferencesContentStateTests.swift`

- [ ] **Step 1: Write failing filtering and selection tests**

Create tests:

```swift
@testable import AppUI
import DictionaryStore
import TranscriptHistoryStore
import XCTest

final class PreferencesContentStateTests: XCTestCase {
    func testHistoryFilterMatchesTextCaseInsensitively() {
        let first = TranscriptRecord(id: UUID(), createdAt: .now, text: "Deploy Kubernetes")
        let second = TranscriptRecord(id: UUID(), createdAt: .distantPast, text: "Book flight")
        XCTAssertEqual(PreferencesContentState.filteredHistory([first, second], query: "KUBE"), [first])
    }

    func testHistorySelectionFallsBackToFirstVisibleRecord() {
        let record = TranscriptRecord(id: UUID(), createdAt: .now, text: "visible")
        XCTAssertEqual(
            PreferencesContentState.resolvedHistorySelection(currentID: UUID(), visibleRecords: [record]),
            record.id
        )
    }

    func testDictionaryFilterMatchesEitherColumn() {
        let entries = [
            DictionaryEntry(wrong: "post grass", correct: "Postgres"),
            DictionaryEntry(wrong: "cube", correct: "Kubernetes")
        ]
        XCTAssertEqual(PreferencesContentState.filteredDictionary(entries, query: "POST"), [entries[0]])
        XCTAssertEqual(PreferencesContentState.filteredDictionary(entries, query: "KUBE"), [entries[1]])
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter PreferencesContentStateTests
```

Expected: build failure because `PreferencesContentState` does not exist.

- [ ] **Step 3: Implement pure state helpers**

Create:

```swift
import DictionaryStore
import Foundation
import TranscriptHistoryStore

enum PreferencesContentState {
    static func filteredHistory(_ records: [TranscriptRecord], query: String) -> [TranscriptRecord] {
        guard !query.isEmpty else { return records }
        return records.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    static func resolvedHistorySelection(currentID: UUID?, visibleRecords: [TranscriptRecord]) -> UUID? {
        if let currentID, visibleRecords.contains(where: { $0.id == currentID }) { return currentID }
        return visibleRecords.first?.id
    }

    static func filteredDictionary(_ entries: [DictionaryEntry], query: String) -> [DictionaryEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.wrong.localizedCaseInsensitiveContains(query)
                || $0.correct.localizedCaseInsensitiveContains(query)
        }
    }
}
```

- [ ] **Step 4: Run state tests**

Run:

```bash
swift test --filter PreferencesContentStateTests
```

Expected: all tests pass.

- [ ] **Step 5: Commit state helpers**

```bash
git add Sources/AppUI/PreferencesContentState.swift Tests/AppUITests/PreferencesContentStateTests.swift
git commit -m "Add preferences content state helpers"
```

---

### Task 5: Wire Persistent History Into the Runtime and Menubar

**Files:**
- Modify: `Sources/AppUI/AppRuntime.swift`
- Modify: `Sources/AppUI/ScrawlApplication.swift`

- [ ] **Step 1: Wire the history store through `AppRuntime`**

Import `TranscriptHistoryStore`, add:

```swift
public let transcriptHistoryStore: any TranscriptHistoryStoring
```

Add it to the initializer and assign it. In `live()`, create:

```swift
let historyURL = appSupportDirectory.appending(path: "history.json")
```

and pass:

```swift
transcriptHistoryStore: JSONTranscriptHistoryStore(fileURL: historyURL)
```

- [ ] **Step 2: Replace the app delegate's in-memory history**

Delete the private `TranscriptRecord` type and `transcriptHistory` array. Add:

```swift
private lazy var transcriptHistoryCoordinator = TranscriptHistoryCoordinator(
    settingsStore: runtime.settingsStore,
    historyStore: runtime.transcriptHistoryStore
)
```

Update all reads to use `runtime.transcriptHistoryStore.records()`.

Update `addTranscriptToHistory`:

```swift
private func addTranscriptToHistory(_ text: String) {
    do {
        try transcriptHistoryCoordinator.add(text: text)
        refreshHistoryMenu()
        refreshPreferencesWindow()
    } catch {
        setStatus("History error: \(describe(error))")
    }
}
```

- [ ] **Step 3: Make the menubar reflect persistent and disabled states**

At the start of `refreshHistoryMenu()`, load settings. If history is disabled, add one disabled item titled `Transcript history is off`. Otherwise, render only the newest 12 records from:

```swift
runtime.transcriptHistoryStore.records().prefix(12)
```

Update `repasteTranscript` to find the ID in the store records.

- [ ] **Step 4: Build and run the full test suite**

Run:

```bash
swift test
```

Expected: build succeeds and all tests pass.

- [ ] **Step 5: Commit runtime integration**

```bash
git add Sources/AppUI/AppRuntime.swift Sources/AppUI/ScrawlApplication.swift
git commit -m "Persist transcript history in app runtime"
```

---

### Task 6: Replace the Segmented Window With the Compact Sidebar Shell

**Files:**
- Create: `Sources/AppUI/PreferencesPageSupport.swift`
- Create: `Sources/AppUI/PreferencesGeneralView.swift`
- Create: `Sources/AppUI/PreferencesModelsView.swift`
- Create: `Sources/AppUI/PreferencesKeyboardView.swift`
- Create: `Sources/AppUI/PreferencesAboutView.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`

- [ ] **Step 1: Create shared page support**

Add reusable AppKit helpers for page headers, bordered groups, rows, separators, and secondary buttons. The key page API is:

```swift
enum PreferencesPageSupport {
    static func makePageHeader(title: String, description: String) -> NSView
    static func makeGroup(rows: [NSView]) -> NSView
    static func makeSettingRow(title: String, detail: NSTextField, action: NSButton?) -> NSView
    static func configureSecondaryButton(_ button: NSButton)
}
```

Use leading/trailing constraints instead of fixed page widths so pages resize with the window.

- [ ] **Step 2: Move existing page behavior into focused views**

Create page views with these update surfaces:

```swift
final class PreferencesGeneralView: NSView {
    func update(settings: AppSettings, microphoneStatus: PermissionStatus, accessibilityStatus: PermissionStatus, isCapturingHotkey: Bool)
}

final class PreferencesModelsView: NSView {
    func update(rows: [PreferencesModelRow], downloadableModels: [DownloadableModel], isDownloadInProgress: Bool)
}

final class PreferencesKeyboardView: NSView {
    func update(hotkey: HotkeySetting, isCapturing: Bool)
}

final class PreferencesAboutView: NSView {
    init(openProjectPage: @escaping () -> Void)
}
```

General shows summaries without edit buttons for model or keyboard. Models preserves select/download/delete actions. Keyboard includes the three gesture instructions from the spec. About reads:

```swift
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
```

and opens `https://github.com/Jetemple/Scrawl`.

- [ ] **Step 3: Rebuild `PreferencesWindowController` as the sidebar shell**

Use:

```swift
enum Section: Int, CaseIterable {
    case general, models, keyboard, history, dictionary, about
}
```

Create an `NSWindow` with:

```swift
contentRect: NSRect(x: 0, y: 0, width: 680, height: 460)
styleMask: [.titled, .closable, .resizable]
window.minSize = NSSize(width: 620, height: 400)
window.title = "Scrawl"
```

Use an `NSSplitView` with a fixed-width 150-point sidebar and flexible content area. Use an `NSTableView` or source-list-style sidebar for section selection. Keep `selectedSection` when the window closes and reopens.

- [ ] **Step 4: Route the existing snapshot and actions**

Keep model, hotkey, and permission closures in `Actions`. Update the controller's `Snapshot` and `update(snapshot:)` to route existing state into the General, Models, and Keyboard page views. Instantiate simple empty-state History and Dictionary container views in the shell; Tasks 7 and 8 replace them.

- [ ] **Step 5: Build and manually smoke-test the shell**

Run:

```bash
swift build --product ScrawlApp
SCRAWL_DEBUG=1 swift run ScrawlApp
```

Verify:

- Window opens at 680 by 460 and cannot shrink below 620 by 400.
- Sidebar switches all six pages.
- General, Models, Keyboard, and About are usable.
- Model and hotkey actions still work.

- [ ] **Step 6: Commit the sidebar shell**

```bash
git add Sources/AppUI/PreferencesPageSupport.swift Sources/AppUI/PreferencesGeneralView.swift Sources/AppUI/PreferencesModelsView.swift Sources/AppUI/PreferencesKeyboardView.swift Sources/AppUI/PreferencesAboutView.swift Sources/AppUI/PreferencesWindowController.swift
git commit -m "Replace preferences tabs with sidebar window"
```

---

### Task 7: Build the History Workspace and Privacy Actions

**Files:**
- Create: `Sources/AppUI/PreferencesHistoryView.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Sources/AppUI/ScrawlApplication.swift`

- [ ] **Step 1: Define History page actions and snapshot data**

Extend `PreferencesWindowController.Actions` with:

```swift
let setTranscriptHistoryEnabled: (Bool) -> Void
let copyTranscript: (UUID) -> Void
let repasteTranscript: (UUID) -> Void
let deleteTranscripts: (Set<UUID>) -> Void
let addDictionaryEntry: (String, String) throws -> Void
```

Extend `Snapshot` with:

```swift
let transcriptHistory: [TranscriptRecord]
let dictionaryEntries: [DictionaryEntry]
```

- [ ] **Step 2: Build the two-pane History view**

Create `PreferencesHistoryView` with:

```swift
final class PreferencesHistoryView: NSView {
    struct Actions {
        let setEnabled: (Bool) -> Void
        let copy: (UUID) -> Void
        let repaste: (UUID) -> Void
        let delete: (Set<UUID>) -> Void
        let addDictionaryEntry: (String, String) throws -> Void
    }

    func update(records: [TranscriptRecord], isEnabled: Bool)
}
```

Use:

- `NSSearchField` and `NSTableView` in the left pane.
- A selectable, non-editable `NSTextView` in the right pane.
- Timestamp and word-count labels.
- Delete, Copy, Paste Again, and Add to Dictionary buttons.
- Disabled and empty explanatory states.

Use `PreferencesContentState` for filtering and selection fallback.

- [ ] **Step 3: Add the selection-anchored dictionary popover**

Enable Add to Dictionary only when `textView.selectedRange().length > 0`. Read the selection with:

```swift
let selectedText = (textView.string as NSString).substring(with: textView.selectedRange())
```

Show an `NSPopover` anchored to the Add to Dictionary button or the selected-text rect when available. Prefill both fields with `selectedText`. Keep the popover open and show an inline error label if `addDictionaryEntry` throws.

- [ ] **Step 4: Coordinate destructive privacy and history actions**

In `ScrawlApplication`, wire History actions. Disabling uses an `NSAlert` with destructive confirmation:

```swift
alert.messageText = "Turn Off Transcript History?"
alert.informativeText = "This permanently deletes all saved transcripts on this Mac."
alert.addButton(withTitle: "Turn Off and Delete")
alert.addButton(withTitle: "Cancel")
```

Only call `transcriptHistoryCoordinator.setEnabled(false)` after confirmation. On success, refresh settings, History, and the menubar. On failure, show an alert/status and refresh from stores.

Copy writes the transcript text to `NSPasteboard.general`. Repaste uses the existing paste path. Delete removes IDs from the history store and refreshes both views.

- [ ] **Step 5: Build and manually verify History**

Run:

```bash
swift build --product ScrawlApp
SCRAWL_DEBUG=1 swift run ScrawlApp
```

Verify search, selection fallback, copy, repaste, single delete, text selection, dictionary popover, disabled state, cancel-disable, and confirmed immediate deletion.

- [ ] **Step 6: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit History UI**

```bash
git add Sources/AppUI/PreferencesHistoryView.swift Sources/AppUI/PreferencesWindowController.swift Sources/AppUI/ScrawlApplication.swift
git commit -m "Add transcript history workspace"
```

---

### Task 8: Build the Dictionary Manager

**Files:**
- Create: `Sources/AppUI/PreferencesDictionaryView.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Sources/AppUI/ScrawlApplication.swift`

- [ ] **Step 1: Define Dictionary actions**

Extend `PreferencesWindowController.Actions` with:

```swift
let saveDictionaryEntry: (String?, String, String) throws -> Void
let deleteDictionaryEntries: (Set<String>) throws -> Void
```

The optional first argument is the original heard-text key when editing and `nil` when adding. Use heard text (`wrong`) as the stable case-insensitive identity for selected rows.

- [ ] **Step 2: Build the searchable Dictionary table**

Create:

```swift
final class PreferencesDictionaryView: NSView {
    struct Actions {
        let save: (String?, String, String) throws -> Void
        let delete: (Set<String>) throws -> Void
    }

    func update(entries: [DictionaryEntry])
}
```

Use `NSSearchField` and a two-column `NSTableView` labeled `Heard Text` and `Replace With`. Filter through `PreferencesContentState.filteredDictionary`.

Provide:

- Add Replacement button.
- Edit button.
- Double-click edit.
- Delete key support.
- Empty and no-search-results states.

- [ ] **Step 3: Reuse one compact Add/Edit sheet**

The sheet contains heard-text and replacement-text fields, inline validation, Cancel, and Save. For editing, prefill the selected entry and retain its original heard-text key. Add calls `addOrReplace`; Edit calls `replace(originalWrong:wrong:correct:)`. Keep the sheet open and show an inline error if saving fails.

Delete one row directly. If more than one row is selected, require confirmation before calling `delete(wrongValues:)`.

- [ ] **Step 4: Wire Dictionary actions and refreshes**

In `ScrawlApplication`, save through:

```swift
if let originalWrong {
    try runtime.dictionaryStore.replace(originalWrong: originalWrong, wrong: wrong, correct: correct)
} else {
    try runtime.dictionaryStore.addOrReplace(wrong: wrong, correct: correct)
}
```

and delete through:

```swift
try runtime.dictionaryStore.delete(wrongValues: wrongValues)
```

After each successful mutation, refresh the preferences snapshot so both Dictionary and any open History popover state see current entries. Report failures visibly and leave the existing UI state intact.

- [ ] **Step 5: Build and manually verify Dictionary**

Run:

```bash
swift build --product ScrawlApp
SCRAWL_DEBUG=1 swift run ScrawlApp
```

Verify search by both columns, add, case-insensitive replace, edit, single delete, multi-delete confirmation, and additions from History.

- [ ] **Step 6: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit Dictionary UI**

```bash
git add Sources/AppUI/PreferencesDictionaryView.swift Sources/AppUI/PreferencesWindowController.swift Sources/AppUI/ScrawlApplication.swift
git commit -m "Add dictionary manager"
```

---

### Task 9: Final Integration, Documentation, and Manual Verification

**Files:**
- Modify: `README.md`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Sources/AppUI/PreferencesHistoryView.swift`
- Modify: `Sources/AppUI/PreferencesDictionaryView.swift`

- [ ] **Step 1: Update user-facing documentation**

Document:

- Settings are available through `Preferences...`.
- History is stored locally, enabled by default, and can be disabled to immediately delete saved transcripts.
- History retains the newest 100 transcripts.
- Selected transcript text can create Dictionary replacements.
- Dictionary replacements remain local.

- [ ] **Step 2: Verify resizing and appearance**

Run:

```bash
SCRAWL_DEBUG=1 swift run ScrawlApp
```

Manually verify at 620 by 400, 680 by 460, and a larger size:

- No clipped controls or fixed-width constraint warnings.
- History and Dictionary panes resize sensibly.
- General, Models, and Keyboard do not waste excessive space.
- Light and dark appearance remain readable.

- [ ] **Step 3: Verify existing product behavior**

Manually verify:

- Microphone and Accessibility actions.
- Model select/download/delete.
- Hotkey capture and gesture instructions.
- Record, transcribe, paste, overlay, and menubar status behavior are unchanged.
- Recent Transcripts menubar submenu shows newest 12 stored records and reports when history is off.
- About project link opens successfully.

- [ ] **Step 4: Run final automated verification**

Run:

```bash
swift test
swift build -c release --product ScrawlApp
git diff --check
git status --short
```

Expected:

- All tests pass.
- Release build succeeds.
- `git diff --check` prints nothing.
- `git status --short` shows only intended changes, if any remain uncommitted.

- [ ] **Step 5: Commit final integration**

```bash
git add README.md Sources/AppUI/PreferencesWindowController.swift Sources/AppUI/PreferencesHistoryView.swift Sources/AppUI/PreferencesDictionaryView.swift
git commit -m "Finish sidebar settings redesign"
```
