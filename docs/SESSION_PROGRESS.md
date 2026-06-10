# Sidebar Settings Redesign Progress

Updated: 2026-06-07

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

The original sidebar pass is complete. A repair pass is now implemented to simplify History and replace correction-pair Dictionary behavior with prompt-based Vocabulary.

Latest automated verification:

- `swift test`: 122 passed
- `swift build -c release --product ScrawlApp`: passed
- `git diff --check`: passed

Repair pass:

- History is a compact single-column feed with word count, recording duration, WPM, and transcription latency.
- History supports search, copy, repaste, delete, and the existing privacy control. Dictionary actions were removed.
- Dictionary is now user-facing Vocabulary: a searchable list of preferred terms.
- Vocabulary terms are sent to `whisper-cli` through `--prompt`; transcripts are no longer rewritten afterward.
- Existing correction entries migrate by retaining their corrected values as preferred terms.
- `make run` stops an installed Scrawl instance before launching the current source build.

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

Commits:

- `b4148d4` Persist transcript history in app runtime
- `0b80419` Harden transcript history runtime integration
- `db8b3aa` Guard delayed history failure presentation
- `148cdb3` Guard delayed history errors by status generation

Implemented:

- Live `history.json` store in `AppRuntime`
- One lazy `TranscriptHistoryCoordinator`
- Store-backed transcript reads
- Persistent repaste lookup
- History-off menubar state
- Menubar renders newest 12 stored transcripts

### Task 6

Commits:

- `a15c241` Replace preferences tabs with sidebar window
- `afd8cd7` Fix preferences sidebar layout quality

Implemented the compact, resizable 680 by 460 sidebar window with General, Models, Keyboard, History, Dictionary, and About pages. Minimum size is 620 by 400.

### Task 7

Commits:

- `154dedc` Add transcript history workspace
- `4d7d4d8` Fix transcript history action handling

Implemented the searchable two-pane History workspace with copy, repaste, delete, privacy toggle, disabled/error states, and selected-text Add to Dictionary.

### Task 8

Commit:

- `1ea16fb` Add dictionary manager

Implemented the searchable two-column Dictionary manager with add/edit sheet, double-click editing, delete-key support, and multi-delete confirmation.

### Task 9

Completed the integration review and documentation update. Final automated checks:

```bash
swift test
swift build -c release --product ScrawlApp
git diff --check
git status --short
```

No remaining code-review findings. Interactive checks still worth performing before release: light/dark appearance, permission actions, model actions, hotkey capture, history privacy behavior, dictionary interactions, and unchanged recording/transcription behavior.
