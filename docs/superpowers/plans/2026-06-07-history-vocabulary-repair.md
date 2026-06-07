# History and Vocabulary Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace correction-pair Dictionary behavior with prompt-based Vocabulary, rebuild History as a compact feed with performance metrics, and make local source launches unambiguous.

**Architecture:** Preserve the existing module boundaries while changing the DictionaryStore module's public model to preferred terms and extending transcription/history models with prompt and timing metadata. Runtime coordination supplies prompt context before transcription and persists metrics afterward; focused AppKit views render the simplified History and Vocabulary experiences.

**Tech Stack:** Swift 5.10, AppKit, Swift Package Manager, whisper.cpp CLI, XCTest

---

### Task 1: Preferred-Term Vocabulary Storage

**Files:**
- Modify: `Sources/DictionaryStore/DictionaryStore.swift`
- Modify: `Tests/DictionaryStoreTests/DictionaryReplacerTests.swift`

- [ ] Add failing tests proving legacy `{wrong, correct}` JSON migrates to corrected preferred terms, and preferred terms support add, edit, delete, case-insensitive deduplication, ordering, persistence, and failed-write cache safety.
- [ ] Run `swift test --filter DictionaryReplacerTests` and verify the new tests fail because the preferred-term API does not exist.
- [ ] Replace `DictionaryEntry`/replacement APIs with `VocabularyTerm` and explicit `add`, `replace`, and `delete` APIs. Decode both preferred-term JSON and legacy dictionary-pair JSON, migrating corrected values.
- [ ] Run `swift test --filter DictionaryReplacerTests` and verify all storage tests pass.
- [ ] Commit with `git commit -m "Replace dictionary mappings with vocabulary terms"`.

### Task 2: Whisper Prompt Context

**Files:**
- Modify: `Sources/TranscriptionCore/TranscriptionCore.swift`
- Modify: `Sources/WhisperCppProvider/WhisperCppProvider.swift`
- Modify: `Tests/WhisperCppProviderTests/WhisperCppPostProcessingTests.swift`

- [ ] Add failing tests proving `TranscriptionRequest` carries optional prompt context and `makeCLIArguments` emits `--prompt` only for non-empty context.
- [ ] Run `swift test --filter WhisperCppPostProcessingTests` and verify the tests fail.
- [ ] Add optional `promptContext` to `TranscriptionRequest` and append `--prompt` in `WhisperCppProvider.makeCLIArguments`.
- [ ] Run `swift test --filter WhisperCppPostProcessingTests` and verify all provider tests pass.
- [ ] Commit with `git commit -m "Pass vocabulary context to whisper"`.

### Task 3: History Timing Metadata

**Files:**
- Modify: `Sources/AudioCapture/AudioCaptureService.swift`
- Modify: `Sources/TranscriptHistoryStore/TranscriptHistoryStore.swift`
- Modify: `Sources/AppUI/TranscriptHistoryCoordinator.swift`
- Modify: `Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift`
- Modify: `Tests/TranscriptHistoryStoreTests/TranscriptHistoryStoreTests.swift`
- Modify: `Tests/AppUITests/TranscriptHistoryCoordinatorTests.swift`

- [ ] Add failing tests proving captured audio exposes duration, new history records persist recording/transcription timing, and legacy history JSON decodes with missing timings.
- [ ] Run the focused AudioCapture, TranscriptHistoryStore, and TranscriptHistoryCoordinator suites and verify the new tests fail.
- [ ] Introduce `CapturedAudio(url:durationMS:)`, change `AudioCaptureServing.stopCapture`, add optional timing fields to `TranscriptRecord`, and extend coordinator `add`.
- [ ] Update test doubles and run the focused suites until they pass.
- [ ] Commit with `git commit -m "Persist transcript performance metrics"`.

### Task 4: Runtime Vocabulary and Metrics Wiring

**Files:**
- Modify: `Sources/AppUI/ScrawlApplication.swift`
- Modify: `Sources/AppUI/AppRuntime.swift`
- Modify: `Tests/AppUITests/AppRuntimeResolutionTests.swift`

- [ ] Add failing pure/helper tests for deterministic, trimmed, case-insensitively deduplicated, bounded Vocabulary prompt construction.
- [ ] Run focused AppUI tests and verify the tests fail.
- [ ] Supply Vocabulary prompt context in each transcription request, remove post-transcription replacement, and pass capture duration plus transcription latency into History.
- [ ] Update preferences snapshots/actions from dictionary entries to vocabulary terms.
- [ ] Run focused AppUI tests and verify they pass.
- [ ] Commit with `git commit -m "Use vocabulary prompts during transcription"`.

### Task 5: Compact History Feed

**Files:**
- Modify: `Sources/AppUI/PreferencesHistoryView.swift`
- Modify: `Sources/AppUI/PreferencesContentState.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Tests/AppUITests/PreferencesContentStateTests.swift`
- Modify: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

- [ ] Add failing tests for History metric formatting, day grouping, removal of Add to Dictionary behavior, and minimum/default window layout.
- [ ] Run focused AppUI tests and verify the new tests fail.
- [ ] Replace the master/detail History UI with a single-column feed containing search, privacy control, transcript text, metrics, and Copy/Paste Again/Delete actions.
- [ ] Run focused AppUI tests and verify they pass.
- [ ] Commit with `git commit -m "Simplify transcript history feed"`.

### Task 6: Vocabulary Preferences Page

**Files:**
- Create: `Sources/AppUI/PreferencesVocabularyView.swift`
- Delete: `Sources/AppUI/PreferencesDictionaryView.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Sources/AppUI/ScrawlApplication.swift`
- Modify: `Tests/AppUITests/PreferencesContentStateTests.swift`
- Modify: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

- [ ] Add failing tests for Vocabulary naming, filtering, selection, empty state, and minimum-window layout.
- [ ] Run focused AppUI tests and verify the new tests fail.
- [ ] Build the Vocabulary page with one preferred-term field, Add Term, searchable term list, edit, delete, and multi-delete confirmation.
- [ ] Update sidebar labels, snapshots, and actions to Vocabulary terminology.
- [ ] Run focused AppUI tests and verify they pass.
- [ ] Commit with `git commit -m "Replace dictionary page with vocabulary"`.

### Task 7: Unambiguous Local Launch

**Files:**
- Create: `scripts/run-local.sh`
- Modify: `Makefile`
- Modify: `README.md`
- Modify: `docs/SESSION_PROGRESS.md`

- [ ] Add a shell-level verification that an installed Scrawl process is stopped before the current source build launches.
- [ ] Implement `scripts/run-local.sh` with normal and explicit `--debug` modes; normal mode must not set `SCRAWL_DEBUG`.
- [ ] Add `make run` and `make run-debug`, document debug-only Control-R/Control-S actions, and update session progress.
- [ ] Run script syntax checks and verify the installed-app conflict behavior.
- [ ] Commit with `git commit -m "Make local Scrawl launches unambiguous"`.

### Task 8: Final Integration Verification

**Files:**
- Review all modified files

- [ ] Run `swift test`.
- [ ] Run `swift build -c release --product ScrawlApp`.
- [ ] Run `git diff --check`.
- [ ] Run a normal local-launch smoke test and confirm no debug manual-recording shortcuts are exposed.
- [ ] Inspect the branch-wide diff against the approved repair spec and fix any remaining findings.
- [ ] Update `docs/SESSION_PROGRESS.md` with final evidence and commit.
