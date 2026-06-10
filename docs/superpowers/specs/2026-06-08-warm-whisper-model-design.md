# Warm Whisper Model Design

## Goal

Reduce release-to-paste latency by retaining the selected Whisper model in a local
`whisper-server` helper between transcriptions, while preserving low idle resource
usage through configurable automatic offloading.

## Measured Baseline

Benchmarked on June 8, 2026 using the installed `ggml-small.en` model and the
11-second whisper.cpp JFK sample:

- One-shot `whisper-cli`: 1.09s and 1.11s, averaging 1.10s.
- Persistent `whisper-server`, configured with the CLI's equivalent beam and
  best-of settings: 0.418s, 0.360s, and 0.359s, averaging 0.379s.
- Server startup to ready: 0.357s.

Warm model reuse reduced request latency by about 65%. Starting the helper when
recording begins can overlap the initial model load with speech.

## Architecture

`WhisperCppProvider` remains the app's transcription provider and retains its
existing one-shot CLI implementation as the reliability fallback. It gains a
private local-server manager that:

- Resolves `whisper-server` beside the configured `whisper-cli`.
- Starts one loopback-only helper for the selected model.
- Sends audio and prompt context through multipart HTTP requests.
- Serializes requests because one helper serves one loaded model.
- Restarts when the selected model or GPU configuration changes.
- Stops after the configured idle timeout or when Scrawl quits.
- Falls back to `whisper-cli` when the server is missing, fails to start, or a
  request fails.

The helper binds only to `127.0.0.1` on an available local port. Audio remains
local to the Mac.

## Lifecycle

- App launch does not load a model.
- Recording start asks the provider to warm the selected model asynchronously.
- Transcription reuses the warm helper or waits for an in-progress warmup.
- Each completed request resets the idle timer.
- Model selection changes stop the old helper.
- App termination stops the helper.

## Setting

`AppSettings` stores a model idle-offload interval with a default of five
minutes. General Settings exposes:

- Immediately
- 1 minute
- 5 minutes
- 15 minutes
- Never

Immediately disables warm retention and uses the existing one-shot CLI path.
Changing the setting applies to the current helper without restarting Scrawl.

## Reliability

The server path is an optimization, not a requirement. Any helper startup,
readiness, HTTP, decoding, or execution failure stops the helper and retries the
same request through the existing CLI path. Existing CPU fallback behavior
continues to apply to CLI execution failures.

## Verification

- Unit tests cover setting persistence/defaults, helper argument construction,
  timeout policy, and multipart response decoding.
- App UI tests cover the General Settings offload control.
- Existing provider and full app test suites remain green.
- A local benchmark compares cold CLI and warm server requests using the same
  model and audio.
