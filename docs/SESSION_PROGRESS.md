# Sidebar Settings Redesign Progress

Updated: 2026-06-06

## Goal

Replace Scrawl's segmented settings form with a compact native sidebar window and add persistent, privacy-controlled transcript History plus a complete Dictionary manager.

Approved design:

- `docs/superpowers/specs/2026-06-06-sidebar-settings-history-dictionary-design.md`

Implementation plan:

- `docs/superpowers/plans/2026-06-06-sidebar-settings-history-dictionary.md`

## Resume Location

Work only in this isolated worktree:

```text
/Users/silver-bullet/code/audio-transcript/.worktrees/sidebar-settings-history-dictionary
```

Branch:

```text
feature/sidebar-settings-history-dictionary
```

The original checkout remains at:

```text
/Users/silver-bullet/code/audio-transcript
```

## Current Status

Tasks 1 through 4 are complete and passed both spec-compliance and code-quality review.

Task 5 implementation is committed at `b4148d4` and is awaiting:

1. Spec-compliance review
2. Code-quality review
3. Any review-driven fixes

Tasks 6 through 9 remain.

The latest full-suite evidence before Task 5 was 77 passing tests. Task 5's implementer reported:

- `swift test`: 77 passed
- `swift build`: passed
- `git diff --check`: passed

## Completed Work

### Task 1: Transcript History Store

Commits:

- `19ab1f5` Add persistent transcript history store
- `af7cb67` Protect corrupt transcript history files

Implemented:

- Standalone `TranscriptHistoryStore` module
- In-memory and JSON stores
- Newest-first ordering and 100-record cap
- Atomic JSON writes
- Corrupt-file protection
- Clear-based recovery
- Failed-write cache protection

Review-driven fixes:

- Corrupt/unreadable history no longer gets silently overwritten.
- Single live JSON-store ownership is documented.

### Task 2: History Privacy Setting and Coordinator

Commits:

- `6ef389c` Add transcript history privacy setting
- `5ca38a9` Harden transcript history privacy safety
- `8ccbc5c` Fail closed on corrupted privacy settings

Implemented:

- History enabled by default
- Migration-safe settings decoding
- Clear-before-disable coordinator
- Serialized add/disable operations
- Separate privacy sidecar setting
- Malformed settings fail closed
- Thread-safe `SettingsStore`

Review-driven fixes:

- Concurrent add cannot persist after disable.
- Corrupted settings cannot silently re-enable history.
- Missing settings still default history to enabled.

### Task 3: Dictionary Mutation APIs

Commits:

- `576fac2` Add dictionary mutation APIs
- `6e421a0` Make dictionary mutations atomic
- `756f19e` Expose explicit dictionary mutations

Implemented:

- Case-insensitive delete
- Edit/replace with changed heard-text key
- Atomic explicit mutations
- Edit-order preservation
- Collision handling
- Existing `save(_:)` compatibility
- JSON write-before-cache behavior

### Task 4: Preferences Content State

Commits:

- `f074598` Add preferences content state helpers
- `cef8549` Improve preferences content search

Implemented:

- Pure History filtering and selection fallback
- Pure Dictionary filtering
- Stable input order
- Trimmed search queries
- Native localized/diacritic-insensitive search

### Task 5: Runtime and Menubar Integration

Implementation commit:

- `b4148d4` Persist transcript history in app runtime

Implemented but not yet reviewed:

- Live `history.json` store in `AppRuntime`
- One lazy `TranscriptHistoryCoordinator`
- Store-backed transcript reads
- Persistent repaste lookup
- History-off menubar state
- Menubar renders newest 12 stored transcripts

## Remaining Tasks

### Task 5 Review

Review `b4148d4` against Task 5 in the implementation plan. Fix all spec or quality findings before continuing.

### Task 6

Replace the segmented settings window with the compact 680 by 460 sidebar shell:

- General
- Models
- Keyboard
- History
- Dictionary
- About

Minimum window size: 620 by 400.

### Task 7

Build the History workspace:

- Searchable two-pane layout
- Copy, repaste, delete
- Save-history toggle and destructive confirmation
- Text selection to Add to Dictionary popover

### Task 8

Build the Dictionary manager:

- Searchable table
- Add/Edit sheet
- Delete and multi-delete confirmation
- Shared mutation APIs

### Task 9

Finish integration and documentation, then run:

```bash
swift test
swift build -c release --product ScrawlApp
git diff --check
git status --short
```

Also manually verify resizing, light/dark appearance, model actions, hotkey capture, history privacy behavior, dictionary interactions, and unchanged recording/transcription behavior.

## Workflow

Continue using Superpowers subagent-driven development:

1. Fresh implementation agent per task
2. Spec-compliance review
3. Code-quality review
4. Implementer fixes every finding
5. Re-review until approved

Do not start the next task with open review findings.
