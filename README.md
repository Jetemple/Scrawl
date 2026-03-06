# Scrawl

Local-first voice-to-text for macOS. Press a key, talk, text appears at your cursor. Everything runs on-device via [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — nothing leaves your machine.

## How it works

1. Hold your hotkey (default: `Right Option`)
2. Speak
3. Release — transcript is pasted into whatever app you're focused on

Or double-tap the hotkey to toggle recording on, then single-tap to stop.

## Install

Requires macOS 14+, Xcode command line tools, and `whisper-cli` from whisper.cpp.

```bash
brew install whisper-cpp

git clone https://github.com/Jetemple/Scrawl.git
cd scrawl
make install PREFIX=/Applications
open /Applications/Scrawl.app
```

On first launch, grant **Microphone** and **Accessibility** permissions when prompted.

Download a model from the Models menu — `small.en` is recommended for daily use.

### Permissions after reinstalling

Building from source produces an unsigned binary. macOS tracks Accessibility permission by code signature, so **after every reinstall you'll need to toggle Accessibility off and back on** in System Settings → Privacy & Security → Accessibility.

To avoid this, sign with a stable identity:

```bash
# find your identities
security find-identity -v -p codesigning

# install with a consistent signature
SCRAWL_CODESIGN_IDENTITY="Your Name (TeamID)" make install
```

This makes permissions survive reinstalls.

## Configuration

Scrawl lives in your menubar. From there you can:

- **Change the hotkey** — Set Hotkey, then press any key or modifier
- **Switch models** — tiny.en (fast), small.en (recommended), medium (multilingual)
- **Repaste recent transcripts** — Recent Transcripts submenu

## Development

```bash
make build      # build
make test       # run tests
make clean      # clean build artifacts
make uninstall  # remove app
```

Run directly from source:

```bash
swift run ScrawlApp
```

Override paths via environment variables:

```bash
SCRAWL_WHISPER_EXECUTABLE=/path/to/whisper-cli swift run ScrawlApp
SCRAWL_MODELS_DIR=/path/to/models swift run ScrawlApp
```

Debug mode (shows manual record/stop controls and overlay previews):

```bash
SCRAWL_DEBUG=1 swift run ScrawlApp
```

## License

MIT
