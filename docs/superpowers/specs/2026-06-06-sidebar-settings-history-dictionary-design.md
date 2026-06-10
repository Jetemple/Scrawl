# Sidebar Settings, History, and Dictionary Design

## Summary

Replace Scrawl's segmented settings window with a compact, resizable native macOS sidebar window. The window will organize existing settings more clearly and add useful History and Dictionary workspaces.

The sidebar contains:

- General
- Models
- Keyboard
- History
- Dictionary
- About

The initial implementation should prioritize a coherent native layout and complete interactions. A later pass can refine visual styling without changing the information architecture.

## Window Structure

The settings window defaults to 680 by 460 points and is resizable. Its minimum size is 620 by 400 points. General, Models, and Keyboard should use the compact default size efficiently; History and Dictionary should remain usable at the default size and gain room when the window expands.

Use a native sidebar-selection pattern with one persistent window and one content view per section. The selected section remains selected while the window stays alive.

The window title is `Scrawl`. Each content page has a clear title and a short description. Avoid repeating the same setting on multiple pages.

## Existing Pages

### General

General communicates whether Scrawl is ready to use and contains:

- Current transcription model summary
- Recording shortcut summary
- Microphone permission status and request action
- Accessibility permission status and request action

Model selection and hotkey editing remain on their dedicated pages.

### Models

Models retains current download, select, and delete behavior. It presents installed and available models in one clear list with visible status and action controls.

### Keyboard

Keyboard contains the recording-shortcut capture control and a concise explanation:

- Hold the shortcut to record
- Double-tap to lock recording
- Tap again to stop and transcribe

### About

About contains the app name, version, local-processing/privacy statement, and relevant project links already available to the app.

## Transcript History

### Storage

Introduce a dedicated history-storage boundary modeled after `DictionaryStoring`.

History records contain:

- Stable UUID
- Creation date
- Transcript text

The live implementation stores records as JSON in Scrawl's Application Support directory. History is enabled by default and retains the newest 100 transcripts. New records appear first.

The storage API supports:

- Reading records
- Adding a record
- Deleting selected records
- Clearing all records

History-storage logic is independent of AppKit so ordering, persistence, limits, and deletion behavior can be unit tested.

### Privacy Setting

Add `isTranscriptHistoryEnabled` to `AppSettings`, defaulting to `true`. Existing settings decode with history enabled.

When the user turns history off:

1. Show a destructive confirmation explaining that existing saved transcripts will be deleted.
2. If confirmed, clear persistent history.
3. Save the disabled setting.
4. Stop saving new transcripts.
5. Update the History page and menubar submenu.

If clearing or saving fails, report the failure and do not present a false successful state.

When history is re-enabled, Scrawl starts saving future transcripts. Previously deleted history is not restored.

### History Page

History is a two-pane workspace:

- The left pane contains search and a date-ordered transcript list.
- The right pane contains the selected transcript, timestamp, word count, and actions.

Supported actions:

- Search transcript text
- Copy transcript
- Paste transcript again
- Delete transcript
- Select text and add it to Dictionary

The page includes a `Save transcript history` toggle and states that history is stored only on this Mac. Empty and disabled states explain what the user can do next.

The menubar's Recent Transcripts submenu remains as quick access to the newest records. When history is disabled, it shows that history is off.

### Add to Dictionary

Selecting non-empty text in a transcript exposes an `Add to Dictionary` action. The action opens a small popover anchored near the selection.

The popover contains:

- Heard text, prefilled from the selection
- Replacement text, initially prefilled with the same selection
- Add and Cancel actions

Saving uses the shared dictionary-store API. Success updates the Dictionary page. Failure leaves the popover open and reports the error.

## Dictionary

Dictionary is a searchable replacement manager backed by the existing persistent dictionary store.

The page contains:

- Search across heard and replacement text
- Replacement table with `Heard Text` and `Replace With` columns
- Add Replacement action
- Edit action and double-click editing
- Delete selected entries

Add and Edit use the same compact editor with `heard text -> replacement text` fields. Heard text is matched case-insensitively, consistent with the current store behavior. Adding an existing heard-text key replaces its entry.

Deleting one selected entry happens directly. Deleting multiple selected entries requires confirmation.

## Architecture

### Storage Boundaries

Add a new transcript-history module or similarly isolated storage type with:

- `TranscriptRecord`
- `TranscriptHistoryStoring`
- In-memory implementation for tests
- JSON implementation for the live app

Wire the live JSON store through `AppRuntime`, alongside `SettingsStore` and `DictionaryStoring`.

Extend `DictionaryStoring` only where needed to make add, edit, and delete operations explicit and testable. Preserve its existing replacement behavior.

### UI Boundaries

`PreferencesWindowController` owns AppKit views and emits user actions. It receives a snapshot containing settings, permissions, models, history records, dictionary entries, and transient operation state.

Keep filtering and display-state transformations in small testable state helpers rather than embedding them in AppKit view construction.

`StatusBarAppDelegate` remains the coordinator for runtime actions:

- Saving settings
- Managing models
- Capturing hotkeys
- Reading and mutating history
- Reading and mutating dictionary entries
- Refreshing the settings window and menubar

The redesign should not alter recording, transcription, output, or overlay behavior.

## Error Handling

- Persistent-storage failures show a visible alert or status message.
- Failed destructive operations do not disappear from the UI.
- Empty search results show an explicit empty state.
- Missing selected history or dictionary records clear the detail/editor state safely.
- History disablement is not committed unless clearing stored history succeeds.

## Testing

Add unit tests for:

- History default enabled setting and decoding migration
- History JSON persistence
- Newest-first ordering and 100-record cap
- Add, delete, and clear operations
- No history addition while disabled
- Clear-on-disable coordination
- History search/filter state
- Dictionary search/filter state
- Dictionary add, edit, replace, and delete operations

Run the full Swift test suite. Manually verify:

- Compact default and minimum window sizes
- Sidebar navigation
- Permission actions
- Model actions
- Hotkey capture
- History search, selection, copy, repaste, and delete
- Selection-anchored dictionary popover
- Dictionary add, edit, and delete
- History disable confirmation and immediate deletion
- Menubar history behavior
- Light and dark appearance

## Out of Scope

- Cloud or synced history
- Rich transcript editing
- Tags, folders, or favorites
- Export formats
- History retention settings beyond the fixed 100-record cap
- Major recording-overlay redesign
- Final visual-polish pass
