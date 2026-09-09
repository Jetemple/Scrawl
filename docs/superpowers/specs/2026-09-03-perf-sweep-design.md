# Perf Sweep (Approach B, v2) — Design

**Status:** approved by owner 2026-09-03 (council-reviewed; "as long as nothing breaks").
**Scope:** targeted hot-path perf. No behavior changes, no new
dependencies (Accelerate is a system framework and is itself gated behind a benchmark).
Public types are untouched with one additive exception (see §1): `AudioCaptureServing`
gains an async analysis method with a defaulted protocol-extension implementation, so all
existing conformers and test doubles compile unchanged.
**Non-goal:** the `ScrawlApplication` split, settings-load caching, stat-call caching,
incremental RMS during capture. All deferred with reasons below.

## Background and method

Full-repo sweep for performance wins. Findings were reviewed by a four-seat council
(unanimous approve-with-changes, 2026-09-03). Every council challenge claim below was
re-verified against the code before being folded into this spec; the v1 items that did
not survive are recorded in §7 so a reviewer can see what was deliberately left alone.

Verified baseline facts:

- `DictionaryReplacer.apply(to:)` has **no callers** in `Sources`. The live app uses
  `dictionaryStore.terms()` only (vocabulary prompt in
  `ScrawlApplication.finalizeRecordingAndTranscribe`, prefs display). Dictionary work is
  hygiene, not a hot-path win.
- `WhisperCppProvider.transcribeOnce` already reads the transcript `.txt` first with the
  stdout log as fallback. Only the eager stdout read remains.
- `stopCapture()` (AVAudioFile decode + silence check + active-duration check) runs on the
  `@MainActor` hotkey-release path (`HotkeyMonitor` callbacks hop to `@MainActor`,
  `stopRecordingAndTranscribe` → `finalizeRecordingAndTranscribe` run there). This is the
  largest verified main-thread stall in the release-to-text path.
- History (capped at 100 records) and dictionary writes already run on background queues
  (`historyActionQueue`, `dictionaryActionQueue`, `TranscriptHistoryCoordinator`); reader
  stalls on the store locks are microseconds to low milliseconds.
- `settingsStore.load()` has 19 call sites in `ScrawlApplication` (plus `AppRuntime`,
  `TranscriptHistoryCoordinator`), each a UserDefaults fetch plus JSON decode. Candidate
  for later write-through caching, only with a profile.

## 1. Audio analysis off the main thread + fused pass (headline item)

**Files:** `Sources/AudioCapture/AudioLevelAnalyzer.swift`,
`Sources/AudioCapture/AudioCaptureService.swift`,
`Sources/AppUI/ScrawlApplication.swift` (call-site threading only).

**Changes:**

- Add one fused analysis entry point that decodes once (existing
  `samples(fromFileURL:)`) and computes silence verdict + longest-active run +
  total-active time in a **single** windowed pass, preserving the current
  Double/concatenation/windowing math exactly. `AudioCaptureService.stopCapture`
  calls it once instead of `isLikelySilent` + `longestActiveAudioSeconds` /
  `activeAudioSeconds`.
- Move the decode-plus-analysis work off the main thread by splitting capture finish
  from analysis: `stopCapture` keeps its synchronous signature and fast rejections
  (duration, file size) while a new async analysis method on `AudioCaptureServing`
  (defaulted in a protocol extension) runs decode plus the fused verdict off-main.
  `finalizeRecordingAndTranscribe` awaits it from its existing `Task` context, so the
  main thread suspends instead of stalling. Failure posture is unchanged: a failed
  decode still lets the recording through, matching today's `try?` fallbacks.
- Multi-channel semantics are **preserved** (channel concatenation stays). Mono by
  averaging was considered and rejected for this pass: it changes RMS beyond float
  epsilon and would silently retune silence gating. Any future change there needs an
  explicit owner decision plus threshold recalibration.
- vDSP (`vDSP_rmsqv`) is **gated behind a benchmark**: ship the fused pass first,
  measure, and only vectorize if the fused pass still shows on a profile. No behavior
  may change with vectorization; differential tests decide.

**Contracts:** identical verdicts on all existing fixtures; threshold-boundary
behavior unchanged; no new failure modes on the release path (decode failure still
passes the recording through; analysis never throws to the caller).

## 2. File-backed multipart upload (memory hardening)

**File:** `Sources/WhisperCppProvider/WarmWhisperServer.swift` (`multipartBody` + call site).

**Changes:**

- Stream the multipart body to a temp file in 1 MB chunks (same chunking pattern as
  `ModelDownloadValidator`) and upload file-backed instead of `Data(contentsOf:)` plus
  an in-memory copy (~2× audio size transient → ~1 MB). Wire bytes identical.
- Temp file: unique name, 0600 permissions, same volume as the audio file, deleted
  **after upload completion** (never a synchronous `defer` in the builder — the upload
  is async and a `defer` can unlink under it). Cleanup covered on success, error, and
  cancellation paths.
- Fallback to the current in-memory path **only when staging cannot be created**.
  Never fall back after an ambiguous upload failure (duplicate-inference risk);
  propagate those errors as today.

**Contracts:** byte-identical request bodies (tested against the current builder),
identical error mapping (`URLError.timedOut` → `TranscriptionError.timedOut`, warm-path
fallback decisions untouched).

## 3. Dictionary replacer hygiene (lowest priority, droppable)

**File:** `Sources/DictionaryStore/DictionaryStore.swift` (`DictionaryReplacer` only).

**Changes (and only these):** early return on empty input/entries; allocation-free
case-style detection (scalar checks instead of whole-string `uppercased()` /
`lowercased()` per hit). Sequential per-entry semantics, cascading replacements, and
case-style preservation are unchanged. The single-snapshot `contains` prefilter was
considered and **rejected**: sequential chaining (`a→b` then `b→c`) and Unicode
case-fold divergence (`ß`/`SS`, dotted `İ`) make it unsound. Trie deferred likewise.

**Contracts:** byte-identical outputs on golden tests covering chaining, overlap,
all-caps/title-case/lowercase, punctuation/uncased text, composed Unicode, and empty
inputs.

## 4. Whisper CLI lazy stdout read (one-liner, folded into item 2's work)

**File:** `Sources/WhisperCppProvider/WhisperCppProvider.swift` (`transcribeOnce`).

**Change:** read the stdout log only when the transcript file is missing (or for
failure diagnostics after non-zero exit), instead of unconditionally before the exit
check. Transcript-first precedence and all error mapping unchanged. An existing-but-empty
transcript file keeps current behavior exactly (treated as empty output, no stdout
fallback) — pinned by test, see §5.

## 5. Testing (behavior pins — "nothing breaks" clause)

Existing suites pass **unmodified** as behavior pins:

- `DictionaryReplacerTests`, `JSONDictionaryStoreTests`, `AudioLevelAnalyzerTests`,
  `TranscriptHistoryStoreTests`, `WhisperCppProviderTests`.

New tests:

- Dictionary golden outputs: chaining (`a→b`, `b→c`), overlap, empty entries/input,
  no-match, all-caps/title-case/lowercase, Unicode (`ß`, Turkish `İ`, composed forms).
- Multipart: byte-identity vs the current builder (0-byte, sub-chunk, multi-MB, with
  and without prompt); staging-failure fallback; cleanup on success/error/cancellation;
  permission and same-volume assertions.
- RMS: old-vs-new differential on fixture WAVs (mono, stereo incl. opposite-phase,
  zeros, Int16 extrema, float files, partial trailing windows, exact-threshold
  boundaries); fused-pass agreement with the two legacy entry points (kept as test
  oracles during the change, removed or kept per reviewer taste).
- Threading: stop-capture analysis completes off the main thread (assert no main-thread
  block; e.g. main-thread watchdog or dispatch assertion in test double).
- CLI: file precedence (present/missing/empty transcript), non-zero exit diagnostics
  still include stdout/stderr, temp cleanup on every exit path.

Verification for every change: `make build`, `make test`, `make lint`,
`make format-check`. No completion claim without fresh command output.

## 6. Explicitly out of scope

- `ScrawlApplication` split (maintainability, not perf).
- Settings-load write-through cache (needs a profile; each load is microseconds).
- `resolveModelPath` stat caching (microseconds; staleness risk when users hand-drop
  model files — correctly deferred).
- JSON-store out-of-lock IO (skipped by default): the naive generation-guard design is
  incorrect under concurrent writers (writer B can derive from optimistic writer A and
  persist A's data although A threw); the correct serialized-persistence-executor
  version costs more complexity than microseconds of reader stall. Revivable only as
  snapshot-plus-encode under lock with a serial persistence queue, with reordered-write
  and failure tests.
- Incremental RMS during capture (worthwhile future, needs capture-path design).
- New dependencies of any kind.

## 7. Council record (why v1 differs)

Council 2026-09-03, four seats, unanimous approve-with-changes. Accepted findings
folded above: prefilter unsoundness (all seats), concat-vs-average epsilon
contradiction (all seats), async temp lifetime (glm, grok), duplicate-inference
fallback bound (sol), JSON lost-update analysis (sol), stale item-5 baseline
(glm, sol), settings-load candidate (glm), off-main-thread opportunity (glm),
incremental-RMS future (grok). Brief was privacy-checked CLEAN before brief-only
seats; roster validated with `validate_profiles.py`.
