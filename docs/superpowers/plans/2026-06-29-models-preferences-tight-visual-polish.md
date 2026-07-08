# Models Preferences Tight Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Polish the Models preferences page without changing the model-management workflow.

**Architecture:** Keep `PreferencesModelsView` as the only production UI surface for this pass. Add focused AppKit layout tests first, then tune row/control layout with small stack-view and sizing changes.

**Tech Stack:** Swift Package Manager, AppKit, XCTest.

## Global Constraints

- Keep one rounded list of model rows.
- Keep the existing row actions: select installed models, download missing models, show selected state.
- Keep the existing lower controls: Add Model, Reveal Models Folder, Delete Selected, Cancel Download, and Find Models.
- Do not split installed and available models into separate sections.
- Do not change model ordering, selection behavior, download behavior, deletion behavior, or copy.
- Preserve clean layout at the existing minimum window size of 620 by 400.

---

### Task 1: Add Focused Layout Regression Tests

**Files:**
- Modify: `Tests/AppUITests/PreferencesModelsViewTests.swift`
- Modify: `Sources/AppUI/PreferencesModelsView.swift`

**Interfaces:**
- Consumes: `PreferencesModelsView.update(rows:downloadableModels:isDownloadInProgress:)`
- Produces: `PreferencesModelsView.visibleActionControlsWithinBounds: Bool`
- Produces: `PreferencesModelsView.visibleSelectedIndicatorWidth: CGFloat?`

- [x] **Step 1: Write the failing tests**

Add tests to `Tests/AppUITests/PreferencesModelsViewTests.swift`:

```swift
@MainActor
func testActionControlsFitWhenCancelDownloadIsVisibleAtMinimumWidth() {
    let view = PreferencesModelsView(
        selectModel: { _ in },
        downloadModel: { _ in },
        deleteSelectedModel: {},
        cancelDownload: {},
        addModel: {},
        revealModelsFolder: {},
        openModelSource: {}
    )
    view.frame = NSRect(x: 0, y: 0, width: 440, height: 320)
    view.update(rows: [
        PreferencesModelRow(
            id: "ggml-small.en",
            displayName: "Small (English)",
            isInstalled: true,
            isSelected: true,
            isDownloading: false,
            isCancelled: false,
            downloadProgressText: nil
        ),
    ], downloadableModels: [], isDownloadInProgress: true)
    view.layoutSubtreeIfNeeded()

    XCTAssertTrue(view.visibleActionControlsWithinBounds)
}

@MainActor
func testSelectedIndicatorUsesCompactActionSlot() throws {
    let view = PreferencesModelsView(
        selectModel: { _ in },
        downloadModel: { _ in },
        deleteSelectedModel: {},
        cancelDownload: {},
        addModel: {},
        revealModelsFolder: {},
        openModelSource: {}
    )
    view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
    view.update(rows: [
        PreferencesModelRow(
            id: "ggml-small.en",
            displayName: "Small (English)",
            isInstalled: true,
            isSelected: true,
            isDownloading: false,
            isCancelled: false,
            downloadProgressText: nil
        ),
    ], downloadableModels: [], isDownloadInProgress: false)
    view.layoutSubtreeIfNeeded()

    XCTAssertEqual(try XCTUnwrap(view.visibleSelectedIndicatorWidth), 28, accuracy: 0.5)
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreferencesModelsViewTests`

Expected: FAIL to compile because `visibleActionControlsWithinBounds` and `visibleSelectedIndicatorWidth` do not exist.

- [x] **Step 3: Add minimal test-facing layout accessors**

Add private tracking and internal accessors in `Sources/AppUI/PreferencesModelsView.swift`:

```swift
private var selectedIndicatorView: NSView?

var visibleActionControlsWithinBounds: Bool {
    [addButton, revealButton, deleteButton, cancelButton, findModelsButton]
        .filter { !$0.isHidden }
        .allSatisfy { bounds.contains(convert($0.bounds, from: $0)) }
}

var visibleSelectedIndicatorWidth: CGFloat? {
    selectedIndicatorView?.frame.width
}
```

Reset `selectedIndicatorView = nil` at the start of `update(...)` and assign it to the selected checkmark wrapper in `makeModelRow(...)`.

- [x] **Step 4: Run tests to verify they now reach real layout assertions**

Run: `swift test --filter PreferencesModelsViewTests`

Expected: At least one new test still FAILS against the current layout, proving the polish change is needed.

---

### Task 2: Polish Models Row And Control Layout

**Files:**
- Modify: `Sources/AppUI/PreferencesModelsView.swift`
- Test: `Tests/AppUITests/PreferencesModelsViewTests.swift`
- Test: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

**Interfaces:**
- Consumes: `PreferencesModelRow.statusText`, `PreferencesModelRow.actionTitle`
- Produces: Same UI behavior with improved AppKit layout metrics.

- [x] **Step 1: Implement the minimal layout polish**

In `Sources/AppUI/PreferencesModelsView.swift`:

```swift
private let rowActionWidth: CGFloat = 78
private let selectedIndicatorWidth: CGFloat = 28
```

Use those constants so buttons occupy a compact action slot while the selected indicator uses a balanced smaller slot:

```swift
if row.isSelected {
    let checkmark = NSImageView(image: NSImage(
        systemSymbolName: "checkmark.circle.fill",
        accessibilityDescription: "Selected"
    ) ?? NSImage())
    checkmark.contentTintColor = .systemBlue
    checkmark.symbolConfiguration = .init(pointSize: 13, weight: .medium)
    checkmark.translatesAutoresizingMaskIntoConstraints = false
    checkmark.widthAnchor.constraint(equalToConstant: selectedIndicatorWidth).isActive = true
    actionArea = checkmark
    selectedIndicatorView = checkmark
} else {
    let actionButton = NSButton(title: row.actionTitle, target: self, action: nil)
    actionButton.identifier = NSUserInterfaceItemIdentifier(row.id)
    PreferencesPageSupport.configureSecondaryButton(actionButton)
    actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    if row.isInstalled {
        actionButton.action = #selector(selectModelAction(_:))
        actionButton.isEnabled = row.canSelect
    } else {
        actionButton.action = #selector(downloadModelAction(_:))
        actionButton.isEnabled = row.canDownload && !isDownloadBlocked
    }
    actionButton.translatesAutoresizingMaskIntoConstraints = false
    actionButton.widthAnchor.constraint(equalToConstant: rowActionWidth).isActive = true
    actionArea = actionButton
}
```

Keep name/detail truncation before status/action compression:

```swift
nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
statusLabel.setContentHuggingPriority(.required, for: .horizontal)
statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
```

Tune row insets and control rows:

```swift
rowStack.spacing = 2
rowStack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 12)

buttonRow.alignment = .centerY
buttonRow.spacing = 6
helpRow.spacing = 5
```

- [x] **Step 2: Run focused tests**

Run: `swift test --filter PreferencesModelsViewTests`

Expected: PASS.

- [x] **Step 3: Run minimum-window related tests**

Run: `swift test --filter PreferencesWindowControllerTests/testModelsPageHasUnambiguousLayoutAtMinimumWindowSize`

Expected: PASS.

- [x] **Step 4: Run broader App UI tests touched by this area**

Run: `swift test --filter AppUITests`

Expected: PASS.

- [x] **Step 5: Commit implementation**

```bash
git add Sources/AppUI/PreferencesModelsView.swift Tests/AppUITests/PreferencesModelsViewTests.swift docs/superpowers/plans/2026-06-29-models-preferences-tight-visual-polish.md
git commit -m "Polish models preferences layout"
```
