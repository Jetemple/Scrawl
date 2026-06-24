<p align="center">
  <img src="Config/AppIcon.png" alt="Scrawl" width="128">
</p>

<h1 align="center">Scrawl</h1>

<p align="center">
  <strong>Local voice-to-text for macOS.</strong><br>
  Hold a key, talk, let go — your words land at the cursor. Runs entirely on-device with
  <a href="https://github.com/ggml-org/whisper.cpp">whisper.cpp</a>. No cloud, no account, no telemetry.
</p>

<p align="center">
  <a href="https://github.com/Jetemple/Scrawl/actions/workflows/ci.yml"><img src="https://github.com/Jetemple/Scrawl/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Jetemple/Scrawl/releases/latest"><img src="https://img.shields.io/github/v/release/Jetemple/Scrawl?sort=semver" alt="Latest release"></a>
  <a href="https://github.com/Jetemple/Scrawl/releases"><img src="https://img.shields.io/github/downloads/Jetemple/Scrawl/total" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform: macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
</p>

<!-- TODO: drop a ~5s demo GIF here (hold Right Option → speak → text pastes) as docs/demo.gif. -->

## What it does

Hold your hotkey (default **Right Option**), speak, release. Scrawl transcribes locally and pastes the text into whatever app you're in. Double-tap to keep recording hands-free; tap again to stop.

That's the whole thing — it lives in your menubar.

## Install

macOS 14+ · Apple Silicon or Intel (Apple Silicon is much faster).

**Homebrew**

```bash
brew tap jetemple/tap
brew trust jetemple/tap          # trust the third-party tap (one-time)
brew install --cask scrawl
```

Update later with `brew upgrade --cask scrawl`.

**From source** — needs macOS 14+ and the Xcode command line tools:

```bash
brew install whisper-cpp
git clone https://github.com/Jetemple/Scrawl.git
cd Scrawl && make install PREFIX=/Applications
open /Applications/Scrawl.app
```

On first launch, grant **Microphone** and **Accessibility** when asked. Then open the menubar **Models** menu and download one. `small.en` is the default — fast, English-only, ~470 MB. Pick `medium` (~1.5 GB) for other languages or `large-v3-turbo` (~1.6 GB) for the best accuracy. Focus any text field, hold Right Option, and talk.

## Features

- **Fully local** — audio never leaves your Mac.
- **Lands at the cursor** — inserts into the focused field, or copies to the clipboard if the app blocks paste.
- **Bring your own model** — ships with tiny/small/medium/large-v3-turbo, or load any whisper.cpp ggml model.
- **No reload lag** — the model stays in memory between recordings and unloads when idle. GPU by default, CPU fallback.
- **Custom vocabulary** — teach it names, jargon, and acronyms.
- **History** — last 100 transcripts, searchable, local-only. One switch wipes them.

## Bring your own model

Anything that runs on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) works — quantized builds, [distil-whisper](https://huggingface.co/distil-whisper), or your own fine-tunes — as long as it's a ggml `.bin`.

In **Settings → Models**:

- **Add Model…** — pick a `.bin` you've downloaded; Scrawl verifies it's a real ggml model and imports it.
- **Reveal Models Folder** — drop `ggml-*.bin` files in directly and they show up automatically.

Grab models from [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/main) on Hugging Face — every size, plus `q5`/`q8` quantized variants. Non-Whisper architectures won't load.

## Troubleshooting

<details>
<summary>Permissions reset after a reinstall or upgrade</summary>

Source builds are unsigned by default, so macOS drops the Accessibility grant on reinstall. Sign with a stable identity to keep it across reinstalls:

```bash
security find-identity -v -p codesigning          # find your identity
SCRAWL_CODESIGN_IDENTITY="Your Name (TeamID)" make install
```

If the mic or accessibility gets stuck after an upgrade, reset and relaunch:

```bash
tccutil reset Microphone com.jetemple.scrawl
tccutil reset Accessibility com.jetemple.scrawl
open /Applications/Scrawl.app
```
</details>

<details>
<summary>Text goes to the clipboard instead of pasting</summary>

Something has macOS **Secure Keyboard Entry** switched on — usually a terminal or a password manager — which blocks synthesized ⌘V system-wide. Scrawl inserts into native text fields via the Accessibility API where it can, and falls back to the clipboard otherwise. Press ⌘V to paste, or turn off secure input in the app that grabbed it.
</details>

## Development

```bash
make build      # build
make test       # run tests
make doctor     # check toolchain and dependencies
make run        # run this source build
make run-debug  # same, plus manual record/stop controls for diagnostics
make clean
make uninstall
```

Env overrides:

```bash
SCRAWL_WHISPER_EXECUTABLE=/path/to/whisper-cli make run   # custom whisper binary
SCRAWL_MODELS_DIR=/path/to/models make run                # custom models directory
SCRAWL_WHISPER_THREADS=8 make run                         # cap threads (auto-selects up to 8)
SCRAWL_DISABLE_GPU=1 make run                             # force CPU-only
```

## License

MIT
