# Scrawl

Local-first voice-to-text for macOS. Press a key, talk, text appears at your cursor. Everything runs on-device via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — nothing leaves your machine.

## How it works

1. Hold your hotkey (default: `Right Option`)
2. Speak
3. Release — transcript is pasted into whatever app you're focused on

Or double-tap the hotkey to toggle recording on, then single-tap to stop.

## Install

Requires macOS 14+ and `whisper-cli` from whisper.cpp.

```bash
# install whisper.cpp (if you haven't)
brew install whisper-cpp

# clone and run
git clone https://github.com/TODO/scrawl.git
cd scrawl
swift run ScrawlApp
```

On first launch, grant **Microphone** and **Accessibility** permissions when prompted.

Download a model from the Models menu — `small.en` is recommended for daily use.

## Configuration

Scrawl lives in your menubar. From there you can:

- **Change the hotkey** — Set Hotkey, then press any key or modifier
- **Switch models** — tiny.en (fast), small.en (recommended), medium (multilingual)
- **Repaste recent transcripts** — Recent Transcripts submenu

Dictionary replacements are stored at `~/Library/Application Support/Scrawl/dictionary.json` — add `{"wrong": "...", "correct": "..."}` entries to auto-correct transcription mistakes.

## Advanced

Override paths via environment variables:

```bash
SCRAWL_WHISPER_EXECUTABLE=/path/to/whisper-cli swift run ScrawlApp
SCRAWL_MODELS_DIR=/path/to/models swift run ScrawlApp
```

Debug mode (shows manual record/stop controls and overlay previews):

```bash
SCRAWL_DEBUG=1 swift run ScrawlApp
```

## Development

```bash
swift build   # build
swift test    # run tests
```

## Status

Early build. Usable but rough around the edges.

## License

MIT
