# Scrawl

Scrawl is a small macOS dictation app that stays local.

You hit a hotkey, talk, and it pastes text where your cursor is.

- menubar app
- global hotkey
- local transcription via `whisper.cpp`
- dictionary fixes (`wrong -> correct`)

## Quickstart

### 1. Requirements

- macOS 14+
- Xcode command line tools
- `whisper-cli` installed (`whisper.cpp`)
- At least one Whisper model downloaded

### 2. Run

```bash
swift run ScrawlApp
```

Optional runtime overrides:

- `SCRAWL_WHISPER_EXECUTABLE=/absolute/path/to/whisper-cli`
- `SCRAWL_MODELS_DIR=/absolute/path/to/model-directory`

Default model directory:

- `~/Library/Application Support/Scrawl/models`

### 3. First use

1. Grant Microphone and Accessibility permissions from the app menu.
2. Focus a text field (Terminal, editor, browser).
3. Hold `Right Option`, speak, release.
4. Transcript is pasted at the cursor.

Toggle mode:

1. Double tap hotkey to start recording.
2. Single tap to stop and transcribe.

## Features

- `Set Hotkey...` (saved across runs)
- Model manager:
  - select installed model
  - download common models
  - delete selected model
- Recent transcript history with repaste actions
- Dictionary replacements pipeline (currently file-based, no in-app editor yet)

Dictionary file location:

- `~/Library/Application Support/Scrawl/dictionary.json`

## Status

This is an early build (`v0.0.2` range), but it’s already usable.

## Development

Build:

```bash
swift build
```

Test:

```bash
swift test
```

## Publishing

See [docs/PUBLISH.md](docs/PUBLISH.md) for a minimal GitHub `v0.0.2` publish flow.

## License

MIT. See [LICENSE](LICENSE).
