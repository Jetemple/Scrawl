# Warm Whisper Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retain the selected Whisper model between requests and offload it after a configurable idle period.

**Architecture:** Extend `WhisperCppProvider` with a loopback-only persistent `whisper-server` manager while preserving the current CLI path as automatic fallback. Add a persisted offload policy and a compact General Settings control, and warm the helper when recording starts.

**Tech Stack:** Swift 5.10, AppKit, Foundation `Process` and `URLSession`, whisper.cpp CLI/server, XCTest

---

### Task 1: Persist the offload policy

**Files:**
- Modify: `Sources/SettingsStore/SettingsStore.swift`
- Modify: `Tests/SettingsStoreTests/AppSettingsDecodingTests.swift`

- [ ] Add failing tests for the five-minute default and encode/decode round trip.
- [ ] Run `swift test --filter AppSettingsDecodingTests` and confirm the new tests fail.
- [ ] Add a codable `ModelOffloadPolicy` and `AppSettings.modelOffloadPolicy`.
- [ ] Run `swift test --filter AppSettingsDecodingTests` and confirm it passes.

### Task 2: Add persistent server lifecycle and fallback

**Files:**
- Modify: `Sources/TranscriptionCore/TranscriptionCore.swift`
- Modify: `Sources/WhisperCppProvider/WhisperCppProvider.swift`
- Modify: `Tests/WhisperCppProviderTests/WhisperCppPostProcessingTests.swift`

- [ ] Add failing tests for server executable resolution, server arguments, response decoding, and offload duration mapping.
- [ ] Run `swift test --filter WhisperCppPostProcessingTests` and confirm the new tests fail.
- [ ] Add a warmable-provider protocol and implement helper startup, readiness, multipart requests, idle shutdown, explicit shutdown, and CLI fallback.
- [ ] Run `swift test --filter WhisperCppPostProcessingTests` and confirm it passes.

### Task 3: Wire preload and shutdown into the app

**Files:**
- Modify: `Sources/AppUI/ScrawlApplication.swift`
- Modify: `Sources/AppUI/AppRuntime.swift`
- Modify: `Tests/AppUITests/AppRuntimeResolutionTests.swift`

- [ ] Add failing coverage for the resolved server executable path.
- [ ] Run `swift test --filter AppRuntimeResolutionTests` and confirm it fails.
- [ ] Warm on recording start, apply policy changes, stop on model selection changes, and stop on termination.
- [ ] Run `swift test --filter AppRuntimeResolutionTests` and confirm it passes.

### Task 4: Add the General Settings control

**Files:**
- Modify: `Sources/AppUI/PreferencesGeneralView.swift`
- Modify: `Sources/AppUI/PreferencesWindowController.swift`
- Modify: `Sources/AppUI/ScrawlApplication.swift`
- Modify: `Tests/AppUITests/PreferencesWindowControllerTests.swift`

- [ ] Add a failing UI test for all offload choices and action dispatch.
- [ ] Run `swift test --filter PreferencesWindowControllerTests` and confirm it fails.
- [ ] Add the offload popup and save/apply action.
- [ ] Run `swift test --filter PreferencesWindowControllerTests` and confirm it passes.

### Task 5: Verify behavior and performance

**Files:**
- Modify: `README.md`

- [ ] Document warm retention, the offload setting, and CLI fallback.
- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `git diff --check`.
- [ ] Re-run the cold CLI versus warm server benchmark and record the result.
