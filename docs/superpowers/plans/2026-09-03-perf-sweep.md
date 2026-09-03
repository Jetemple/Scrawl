# Perf Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut hotkey-release-to-text latency and peak transcription memory with zero behavior change.

**Architecture:** Four isolated internal swaps (fused audio analysis, off-main analysis, file-backed upload, dictionary hygiene) plus one one-liner, each independently testable and revertible. Public types untouched except two additive, defaulted `AudioCaptureServing` methods that keep every existing conformer compiling.

**Tech Stack:** Swift 5.10, SwiftPM, XCTest, AVFoundation, Accelerate (conditional on benchmark gate).

**Spec:** `docs/superpowers/specs/2026-09-03-perf-sweep-design.md` — the plan argues from the spec; executors read both.

## Global Constraints

- macOS 14 floor, `swift-tools-version: 5.10`. Follow existing concurrency patterns (`NSLock`, `@unchecked Sendable`); `Task.detached` closures capture only `Sendable` values.
- No behavior changes: identical verdicts, identical wire bytes, identical error mapping and user-visible alerts. Existing suites pass unmodified (new tests are appended, existing tests untouched): `AudioLevelAnalyzerTests`, `AudioCaptureMeteringTests`, `DictionaryReplacerTests`, `JSONDictionaryStoreTests`, `TranscriptHistoryStoreTests`, `WhisperCppProviderTests`, `WarmWhisperServerTests`, `AppUITests`.
- No AI attribution anywhere: no footers, no `Co-Authored-By`, no tool tokens in commits. Commit messages are sentence-case like the repo history (`Build the vocabulary prompt incrementally`).
- No new dependencies. Accelerate only if Task 3's gate passes with measured evidence.
- WORKTREE CAVEAT: branch `fix-update-banner-stale-cache` carries foreign in-flight changes (`M HotkeyMonitor.swift`, `M AudioCaptureService.swift`, untracked `CaptureDiagnostics` files). Never touch, revert, or commit them. Tasks touching `AudioCaptureService.swift` apply on top; start every task with `git status --short` and stop + report if the foreign diff conflicts.
- TDD every task: write the test, run it red, implement minimal code, run green, run the neighboring suite, commit only the task's files. Verification skill applies: no completion claim without fresh command output.
- Approving this plan authorizes its per-task commits on this branch (one commit per task, task files only).

## File Structure

- `Sources/AudioCapture/AudioLevelAnalyzer.swift` — add `AudioAnalysis` + `analyze` (Task 1). No deletions; legacy methods stay as oracles.
- `Sources/AudioCapture/AudioCaptureService.swift` — use fused analysis (Task 1); split finish/analyze + protocol defaults (Task 2).
- `Sources/AppUI/ScrawlApplication.swift` — await analysis in the existing transcribe `Task`, extract error helper (Task 2).
- `Sources/WhisperCppProvider/WarmWhisperServer.swift` — staging writer + file-backed upload (Task 4).
- `Sources/WhisperCppProvider/WhisperCppProvider.swift` — lazy stdout read (Task 5).
- `Sources/DictionaryStore/DictionaryStore.swift` — early return + scalar case-style (Task 6).
- Tests (append-only): `Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift`, `Tests/WhisperCppProviderTests/WarmWhisperServerTests.swift`, `Tests/DictionaryStoreTests/DictionaryReplacerTests.swift`.

---

### Task 1: Fused single-pass audio analysis

**Files:**
- Modify: `Sources/AudioCapture/AudioLevelAnalyzer.swift` (append `AudioAnalysis` + `analyze`)
- Modify: `Sources/AudioCapture/AudioCaptureService.swift` (use fused result internally; keep sync behavior identical)
- Test: `Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift` (append differential tests)

**Interfaces:**
- Consumes: existing `samples(fromFileURL:)`, config values already in `AudioCaptureService`.
- Produces for Task 2: `public struct AudioAnalysis: Sendable, Equatable { isSilent: Bool; longestActiveSeconds: Double; totalActiveSeconds: Double }` and `public static func analyze(samples: [Int16], sampleRate: Double, silenceThresholdRMS: Double, windowSeconds: Double = 0.03, activeRMS: Double = 0.0075) -> AudioAnalysis`.

- [ ] **Step 1: Append the failing differential test**

```swift
func testFusedAnalysisAgreesWithLegacyEntryPoints() {
    let sampleRate: Double = 16000
    // 1s silence, 300ms speech-like burst, 200ms room tone, trailing partial window
    var samples = [Int16](repeating: 0, count: 16000)
    let amp = Int16(Int16.max / 3)
    for i in 16000..<(16000 + 4800) { samples.append((i % 2 == 0) ? amp : -amp) }
    var state: UInt64 = 999
    for _ in 0..<3200 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        samples.append(Int16(Int64(bitPattern: state) % 100))
    }
    samples.append(contentsOf: [Int16](repeating: amp, count: 17)) // partial window
    let fused = AudioLevelAnalyzer.analyze(samples: samples, sampleRate: sampleRate, silenceThresholdRMS: 0.001)
    XCTAssertEqual(fused.isSilent, AudioLevelAnalyzer.isLikelySilent(samples: samples, minimumRMS: 0.001))
    XCTAssertEqual(fused.longestActiveSeconds,
        AudioLevelAnalyzer.longestActiveAudioSeconds(samples: samples, sampleRate: sampleRate), accuracy: 0.0)
    XCTAssertEqual(fused.totalActiveSeconds,
        AudioLevelAnalyzer.activeAudioSeconds(samples: samples, sampleRate: sampleRate), accuracy: 0.0)
}

func testFusedAnalysisEmptyInput() {
    let fused = AudioLevelAnalyzer.analyze(samples: [], sampleRate: 16000, silenceThresholdRMS: 0.001)
    XCTAssertTrue(fused.isSilent)
    XCTAssertEqual(fused.longestActiveSeconds, 0.0)
    XCTAssertEqual(fused.totalActiveSeconds, 0.0)
}
```

- [ ] **Step 2: Run to verify it fails (no `analyze` API yet)**

Run: `swift test --filter AudioLevelAnalyzerTests.testFusedAnalysisAgreesWithLegacyEntryPoints`
Expected: FAIL (compile error: `analyze` does not exist — that is the red).

- [ ] **Step 3: Implement the fused pass** (append to `AudioLevelAnalyzer`; one pass, same arithmetic order as the legacy loops so results are bitwise identical):

```swift
public struct AudioAnalysis: Sendable, Equatable {
    public var isSilent: Bool
    public var longestActiveSeconds: Double
    public var totalActiveSeconds: Double
    public init(isSilent: Bool, longestActiveSeconds: Double, totalActiveSeconds: Double) {
        self.isSilent = isSilent
        self.longestActiveSeconds = longestActiveSeconds
        self.totalActiveSeconds = totalActiveSeconds
    }
}

public static func analyze(
    samples: [Int16],
    sampleRate: Double,
    silenceThresholdRMS: Double,
    windowSeconds: Double = 0.03,
    activeRMS: Double = 0.0075
) -> AudioAnalysis {
    guard !samples.isEmpty, sampleRate > 0, windowSeconds > 0 else {
        return AudioAnalysis(isSilent: true, longestActiveSeconds: 0, totalActiveSeconds: 0)
    }
    let windowSize = max(1, Int(sampleRate * windowSeconds))
    var grandSum = 0.0
    var windowSum = 0.0
    var windowCount = 0
    var totalActive = 0.0
    var currentRun = 0.0
    var longestRun = 0.0
    func closeWindow() {
        let rms = sqrt(windowSum / Double(windowCount))
        if rms >= activeRMS {
            let dur = Double(windowCount) / sampleRate
            totalActive += dur
            currentRun += dur
            longestRun = max(longestRun, currentRun)
        } else {
            currentRun = 0
        }
        windowSum = 0
        windowCount = 0
    }
    for sample in samples {
        let n = Double(sample) / Double(Int16.max)
        grandSum += n * n
        windowSum += n * n
        windowCount += 1
        if windowCount == windowSize { closeWindow() }
    }
    if windowCount > 0 { closeWindow() }
    return AudioAnalysis(
        isSilent: sqrt(grandSum / Double(samples.count)) < silenceThresholdRMS,
        longestActiveSeconds: longestRun,
        totalActiveSeconds: totalActive
    )
}
```

Then in `AudioCaptureService.stopCapture`, replace the `isLikelySilent` + `longest/totalActiveAudioSeconds` calls with one `analyze` call and pick `longestActiveSeconds` vs `totalActiveSeconds` per `config.usesSustainedActiveDuration`. Keep the `samples.isEmpty ||` guard and every rejection branch (including `CaptureDiagnostics` calls) exactly as-is.

- [ ] **Step 4: Run green + neighbors**

Run: `swift test --filter AudioLevelAnalyzerTests`
Expected: PASS (all, old + new).
Run: `swift test --filter AudioCaptureMeteringTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git status --short   # confirm only Task 1 files differ (plus the known foreign diff, left alone)
git add Sources/AudioCapture/AudioLevelAnalyzer.swift Sources/AudioCapture/AudioCaptureService.swift Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift
git commit -m "Fuse audio analysis into a single pass"
```

---

### Task 2: Audio analysis off the main thread

**Files:**
- Modify: `Sources/AudioCapture/AudioCaptureService.swift` (protocol + service)
- Modify: `Sources/AppUI/ScrawlApplication.swift` (call site ~line 1610, error-helper extract)
- Test: `Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift` (append watchdog + parity tests)

**Interfaces:**
- Consumes: Task 1's `AudioAnalysis` + `analyze`.
- Protocol additions (both with defaults so `StubAudioCaptureService` compiles unchanged):
  `func finishCapture() throws -> (url: URL, wallSeconds: Double)` (default: `(try stopCapture(), 0)`)
  `func analyzeCaptureFile(at url: URL, wallSeconds: Double = 0) async throws -> AudioAnalysis` (default: detached decode + default-config verdicts, decode failure passes through).

- [ ] **Step 1: Read the exact call site** — read `ScrawlApplication.swift` lines 1603–1700 (finalize + catch block) and `handleTranscriptionFailure` isolation. The foreign diff touches `AudioCaptureService.swift`, not this file, but re-check `git status --short` first.

- [ ] **Step 2: Append the failing parity + watchdog tests**

```swift
func testAsyncAnalysisParityWithSyncVerdicts() async throws {
    let service = AudioCaptureService()
    let url = try Self.writeWAV(samples: [Int16](repeating: Int16(Int16.max / 3), count: 4800), sampleRate: 16000)
    defer { try? FileManager.default.removeItem(at: url) }
    let analysis = try await service.analyzeCaptureFile(at: url)
    let samples = try AudioLevelAnalyzer.samples(fromFileURL: url)
    XCTAssertEqual(analysis, AudioLevelAnalyzer.analyze(
        samples: samples, sampleRate: 16000, silenceThresholdRMS: service.config.silenceThresholdRMS,
        windowSeconds: service.config.activeWindowSeconds, activeRMS: service.config.activeWindowRMS))
    XCTAssertFalse(analysis.isSilent)
}

@MainActor
func testAnalyzeRunsOffMainThread() async throws {
    let url = try Self.writeWAV(samples: Self.longSpeechLikeBuffer(seconds: 600), sampleRate: 16000)
    defer { try? FileManager.default.removeItem(at: url) }
    var mainWasFree = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { mainWasFree = true }
    _ = try await AudioCaptureService().analyzeCaptureFile(at: url)
    XCTAssertTrue(mainWasFree, "main thread must stay responsive during analysis")
}

private static func writeWAV(samples: [Int16], sampleRate: Double) throws -> URL {
    // AVFoundation WAV writer for tests. Import AVFoundation at the top of the file.
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("scrawl-test-\(UUID().uuidString)").appendingPathExtension("wav")
    let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { src in
        buffer.int16ChannelData![0].update(from: src.baseAddress!, count: samples.count)
    }
    try file.write(from: buffer)
    return url
}

private static func longSpeechLikeBuffer(seconds: Int) -> [Int16] {
    // Alternating 1s speech-like / 1s silence at 16kHz. ~19MB for 600s; generated once per test.
    let amp = Int16(Int16.max / 3)
    var out = [Int16]()
    out.reserveCapacity(seconds * 16000)
    for s in 0..<seconds {
        if s % 2 == 0 {
            for i in 0..<16000 { out.append((i % 2 == 0) ? amp : -amp) }
        } else {
            out.append(contentsOf: [Int16](repeating: 0, count: 16000))
        }
    }
    return out
}
```

- [ ] **Step 3: Run to verify red**

Run: `swift test --filter AudioLevelAnalyzerTests.testAsyncAnalysisParityWithSyncVerdicts`
Expected: FAIL (no `analyzeCaptureFile` / `finishCapture` API).

- [ ] **Step 4: Implement the split.** In `AudioCaptureService.swift`: extract today's recorder-stop + duration/size rejection + `recordCapture` diagnostics into `finishCapture()` returning `(url, wallSeconds)`; extract a private sync `verdict(samples:config:wallSeconds:) throws -> AudioAnalysis` holding the silence/active checks + rejection diagnostics; reimplement `stopCapture()` as `finishCapture` + sync decode + `verdict` (identical behavior, keeps old tests green); add the async `analyzeCaptureFile(at:wallSeconds:)` running decode + `verdict` inside `Task.detached(priority: .userInitiated)`, with decode failure passing the recording through exactly like today's `try?`. Add the two protocol requirements plus the defaults from Interfaces.
- [ ] **Step 5: Rewire the app.** In `finalizeRecordingAndTranscribe`: replace `stopCapture()` with `finishCapture()` (same catch handling via a new `@MainActor ... async func handleStopCaptureError(_:activeOrigin:)` extracted verbatim from today's catch block; the main-thread throw site calls it via `Task { await ... }`); as the first statement of the existing transcribe `Task`, `await analyzeCaptureFile(at:wallSeconds:)` and on throw call the same helper and return (audio file still deleted by the existing `defer`).
- [ ] **Step 6: Run green + neighbors**

Run: `swift test --filter AudioLevelAnalyzerTests`
Expected: PASS.
Run: `swift test --filter AppRuntimeResolutionTests`
Expected: PASS (stub still compiles — proves the defaults work).
Run: `swift test --filter AudioCaptureMeteringTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AudioCapture/AudioCaptureService.swift Sources/AppUI/ScrawlApplication.swift Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift
git commit -m "Analyze capture audio off the main thread"
```

---

### Task 3: Benchmark gate for vDSP (conditional)

**Files:**
- Test: `Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift` (append perf test; kept regardless of outcome)

**Interfaces:** Consumes Task 1's `analyze`. Produces a go/no-go decision with numbers in the commit message.

- [ ] **Step 1: Append the benchmark**

```swift
func testFusedVersusLegacyPerformance() {
    let samples = Self.longSpeechLikeBuffer(seconds: 600)
    measure { _ = AudioLevelAnalyzer.analyze(samples: samples, sampleRate: 16000, silenceThresholdRMS: 0.001) }
}
```

- [ ] **Step 2: Measure both**

Run: `swift test --filter AudioLevelAnalyzerTests.testFusedVersusLegacyPerformance`
Then temporarily measure the legacy pair (add, run, remove — or keep both measures in one run) with the identical buffer: `isLikelySilent` + `longestActiveAudioSeconds`.
Expected: numbers for both, same machine, release-tested binary (`swift test` builds debug; note the configuration in the commit message — debug numbers only gate direction, not absolute claims).

- [ ] **Step 3: Apply the decision rule.** Adopt vDSP (`import Accelerate`, normalize to `Float` once via `vDSP_vflt16` + `vDSP_vsmul` by `1/32767`, per-window `vDSP_rmsqv`) ONLY if fused mean > 0.05s AND the vDSP variant is ≥2× faster with zero verdict flips on every fixture plus 100 randomized buffers (LCG, varying speech/noise mixes, per-window agreement within 1e-6). Otherwise close this task with the numbers as evidence and skip to Task 4.
- [ ] **Step 4 (only if gate passes): implement + differential tests, run full `AudioCaptureTests`, commit**

```bash
git add Sources/AudioCapture/AudioLevelAnalyzer.swift Tests/AudioCaptureTests/AudioLevelAnalyzerTests.swift
git commit -m "Vectorize audio RMS with Accelerate"
```

If gate fails: commit the perf test alone with the numbers (`git commit -m "Add fused-analysis benchmark (vDSP not justified: <numbers>)"`).

---

### Task 4: File-backed multipart upload

**Files:**
- Modify: `Sources/WhisperCppProvider/WarmWhisperServer.swift` (staging writer + `upload(for:fromFile:)`)
- Test: `Tests/WhisperCppProviderTests/WarmWhisperServerTests.swift` (append; file already `@testable` imports)

**Interfaces:**
- Consumes: existing framing (boundary, prompt trimming) — wire bytes must stay identical.
- Produces: `static var stagingDirectory` (internal seam, default `temporaryDirectory`); staging writer used only by `transcribe`.

- [ ] **Step 1: Append the failing byte-identity + failure tests**

```swift
func testStagedMultipartBodyIsByteIdentical() throws {
    let audio = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-test-\(UUID().uuidString).wav")
    let bytes = Data((0..<3_000_000).map { _ in UInt8.random(in: 0...255) })
    try bytes.write(to: audio)
    defer { try? FileManager.default.removeItem(at: audio) }
    for prompt in [nil, "  ", "Preferred vocabulary: Ada, mantra"] {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: staged) }
        try WarmWhisperServer.writeMultipartBody(audioURL: audio, prompt: prompt, boundary: "TEST", to: staged)
        XCTAssertEqual(try Data(contentsOf: staged), try WarmWhisperServer.multipartBody(audioURL: audio, prompt: prompt, boundary: "TEST"))
    }
    // Permissions: owner-only, mirroring the stores.
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent("scrawl-test-\(UUID().uuidString).bin")
    defer { try? FileManager.default.removeItem(at: staged) }
    try WarmWhisperServer.writeMultipartBody(audioURL: audio, prompt: nil, boundary: "TEST", to: staged)
    let perms = try FileManager.default.attributesOfItem(atPath: staged.path)[.posixPermissions] as? Int
    XCTAssertEqual(perms, 0o600)
}

func testStagingFailureThrows() {
    WarmWhisperServer.stagingDirectory = URL(filePath: "/nonexistent-dir-scrawl-test")
    defer { WarmWhisperServer.stagingDirectory = FileManager.default.temporaryDirectory }
    XCTAssertThrowsError(try WarmWhisperServer.writeMultipartBody(
        audioURL: URL(filePath: "/tmp/x.wav"), prompt: nil, boundary: "TEST",
        to: WarmWhisperServer.stagingDirectory.appendingPathComponent("y.bin")))
}
```

Note: `multipartBody` is currently `private static` — make it `static` (internal) as part of this task so the oracle is reachable; no behavior change.

- [ ] **Step 2: Run to verify red**

Run: `swift test --filter WarmWhisperServerTests.testStagedMultipartBodyIsByteIdentical`
Expected: FAIL (no `writeMultipartBody` API).

- [ ] **Step 3: Implement.** Add `writeMultipartBody(audioURL:prompt:boundary:to:)` streaming the identical framing lines via `OutputStream`/`FileHandle` with the audio copied in 1 MB chunks, 0600 permissions set explicitly post-create (umask-independent). In `transcribe`: stage to `stagingDirectory/scrawl-upload-<uuid>.bin`; on staging failure fall back to the existing in-memory `multipartBody` + `data(for:)` path unchanged; on staging success use `URLSession.shared.upload(for: httpRequest, fromFile: stagedURL)` with `httpBody` left nil, deleting the staged file in a `defer` placed AFTER the awaited upload (safe: upload completed). Never fall back after the upload starts — propagate those errors exactly as today.
- [ ] **Step 4: Run green + neighbors**

Run: `swift test --filter WarmWhisperServerTests`
Expected: PASS.
Run: `swift test --filter RoutingTranscriptionProviderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperCppProvider/WarmWhisperServer.swift Tests/WhisperCppProviderTests/WarmWhisperServerTests.swift
git commit -m "Stream warm-server uploads from disk"
```

---

### Task 5: Whisper CLI lazy stdout read

**Files:**
- Modify: `Sources/WhisperCppProvider/WhisperCppProvider.swift` (reorder only)

**Interfaces:** None (pure reorder inside `transcribeOnce`).

- [ ] **Step 1: Reorder.** Delete the eager `let stdout = (try? String(contentsOf: stdoutURL ...)) ?? ""` before the exit check; read the stdout file inside the non-zero-exit branch (for diagnostics) and keep the transcript-file-first selection exactly as-is. An existing-but-empty transcript file keeps current behavior (treated as empty, no stdout fallback). The `defer` cleanup stays last — both reads precede it.
- [ ] **Step 2: Run (existing suite is the test — zero behavior change)**

Run: `swift test --filter WhisperCppProviderTests`
Expected: PASS.
Run: `swift test --filter WhisperCppPostProcessingTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/WhisperCppProvider/WhisperCppProvider.swift
git commit -m "Read whisper stdout lazily"
```

---

### Task 6: Dictionary replacer hygiene + golden tests

**Files:**
- Modify: `Sources/DictionaryStore/DictionaryStore.swift` (`DictionaryReplacer` only)
- Test: `Tests/DictionaryStoreTests/DictionaryReplacerTests.swift` (append goldens)

**Interfaces:** None (same signatures, byte-identical outputs).

- [ ] **Step 1: Capture current outputs for the tricky inputs.** Temporarily append a printing test, run it, paste actuals into the golden table in Step 2, then delete the temp test:

```swift
func testTempPrintTrickyOutputs() {
    let entries = [
        DictionaryEntry(wrong: "a", correct: "b"),
        DictionaryEntry(wrong: "b", correct: "c"),
        DictionaryEntry(wrong: "ss", correct: "ß-out"),
        DictionaryEntry(wrong: "hello", correct: "goodbye"),
    ]
    for text in ["a b", "SS ss", "STRASSE", "İ", "hELLO hello HELLO", " he", "123", "👋 hello"] {
        print("PIN[\(text)]=[\(DictionaryReplacer.apply(entries: entries, to: text))]")
    }
}
```

Run: `swift test --filter DictionaryReplacerTests.testTempPrintTrickyOutputs` and record the `PIN` lines.

- [ ] **Step 2: Write the golden tests with the captured outputs** (plus obvious cases: empty entries → passthrough, empty text → empty, no-match passthrough, single replace, overlap ordering `"he"` vs `"hello"` entries). Delete the temp test.
- [ ] **Step 3: Run green on current code (proves the goldens pin reality)**

Run: `swift test --filter DictionaryReplacerTests`
Expected: PASS.

- [ ] **Step 4: Implement.** Early return (`guard !entries.isEmpty, !text.isEmpty else { return text }`); scalar-property case-style check with the exact-equivalence fallback for the rare mixed-case path:

```swift
private static func applyCaseStyle(from original: String, to replacement: String) -> String {
    let cased = original.unicodeScalars.filter { $0.properties.isCased }
    if cased.allSatisfy({ $0.properties.isUppercase }) { return replacement.uppercased() }
    if cased.allSatisfy({ $0.properties.isLowercase }) { return replacement.lowercased() }
    // Rare mixed-case path: keep the exact legacy grapheme comparison (allocates, but
    // only for mixed-case matches) rather than risk divergence on uncased-first text.
    if original.prefix(1) == original.prefix(1).uppercased(),
       original.dropFirst() == original.dropFirst().lowercased()
    {
        return replacement.prefix(1).uppercased() + replacement.dropFirst().lowercased()
    }
    return replacement
}
```

- [ ] **Step 5: Run green + neighbors**

Run: `swift test --filter DictionaryReplacerTests`
Expected: PASS (goldens identical — proves byte-equivalence).
Run: `swift test --filter JSONDictionaryStoreTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/DictionaryStore/DictionaryStore.swift Tests/DictionaryStoreTests/DictionaryReplacerTests.swift
git commit -m "Trim dictionary replacement overhead"
```

---

### Task 7: Full verification and report

**Files:** None (unless `make format` touches something — commit separately only if so).

- [ ] **Step 1: Fresh full verification**

Run: `make build`
Expected: exit 0.
Run: `make test`
Expected: 0 failures (record the pass count).
Run: `make lint`
Expected: 0 errors.
Run: `make format-check`
Expected: clean (run `make format` first if dirty, then re-verify).

- [ ] **Step 2: Report** state done-verified (with the numbers), done-unverified, blocked, and open decisions — per the "state reality" rule. No `goal_complete`-style claims beyond the evidence.

## Self-Review

**1. Spec coverage:** §1 → Tasks 1–3 (fused, off-main, vDSP gate; concat preserved; additive protocol exception honored). §2 → Task 4 (completion-scoped delete, staging-only fallback, 0600, byte-identity). §3 → Task 6 (prefilter/trie correctly absent). §4 → Task 5 (transcript-first already the code; lazy stdout only). §5 → per-task tests + Task 7 verification. §6 deferrals have no tasks — correct.

**2. Placeholder scan:** every step names exact files, exact API shapes, exact commands with expected outputs. The two "read first" steps (2.1, implicitly 1.x line refs) point at exact line ranges. No TBD/TODO/equivalent.

**3. Type consistency:** `AudioAnalysis(isSilent:longestActiveSeconds:totalActiveSeconds:)` identical in Tasks 1, 2, 4-free; `analyze(samples:sampleRate:silenceThresholdRMS:windowSeconds:activeRMS:)` signature identical everywhere; `finishCapture() -> (url:wallSeconds:)`, `analyzeCaptureFile(at:wallSeconds:)` identical in Task 2 steps and tests; `writeMultipartBody(audioURL:prompt:boundary:to:)` + `stagingDirectory` identical in Task 4 steps/tests; `swift test --filter <RealClassName>` filters all verified against the test files.

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-09-03-perf-sweep.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
