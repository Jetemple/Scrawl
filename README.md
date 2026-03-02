# Scrawl

Local-first voice-to-text for macOS. Press a key, talk, text appears at your cursor. Everything runs on-device via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — nothing leaves your machine.

## How it works

1. Hold your hotkey (default: `Right Option`)
2. Speak
3. Release — transcript is pasted into whatever app you're focused on

Or double-tap the hotkey to toggle recording on, then single-tap to stop.

## Install (App Bundle)

Requires macOS 14+ and `whisper-cli` from whisper.cpp.

```bash
# install whisper.cpp (if you haven't)
brew install whisper-cpp

# clone and install Scrawl.app into ~/Applications
git clone https://github.com/Jetemple/Scrawl.git
cd scrawl
./scripts/install-app.sh
open ~/Applications/Scrawl.app
```

Install system-wide instead:

```bash
./scripts/install-app.sh /Applications
# if needed:
sudo ./scripts/install-app.sh /Applications
```

On first launch, grant **Microphone** and **Accessibility** permissions when prompted.

Download a model from the Models menu — `small.en` is recommended for daily use.

## Configuration

Scrawl lives in your menubar. From there you can:

- **Change the hotkey** — Set Hotkey, then press any key or modifier
- **Switch models** — tiny.en (fast), small.en (recommended), medium (multilingual)
- **Repaste recent transcripts** — Recent Transcripts submenu

## Advanced

Run directly from source (development):

```bash
swift run ScrawlApp
```

Override paths via environment variables (development):

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
