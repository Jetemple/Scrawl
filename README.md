<p align="center">
  <img src="Config/AppIcon.png" alt="Scrawl" width="128">
</p>

<h1 align="center">Scrawl</h1>

<p align="center">
  <strong>Local voice-to-text for macOS.</strong><br>
  Hold a key, talk, let go. Your words appear at the cursor.
  Everything runs on your Mac: Parakeet v3 on Apple Silicon, or <a href="https://github.com/ggml-org/whisper.cpp">whisper.cpp</a> ggml models when you want them. No cloud, no account, no telemetry.
</p>

<p align="center">
  <a href="https://github.com/Jetemple/Scrawl/actions/workflows/ci.yml"><img src="https://github.com/Jetemple/Scrawl/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Jetemple/Scrawl/releases/latest"><img src="https://img.shields.io/github/v/release/Jetemple/Scrawl?sort=semver" alt="Latest release"></a>
  <a href="https://github.com/Jetemple/Scrawl/releases"><img src="https://img.shields.io/github/downloads/Jetemple/Scrawl/total" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform: macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
</p>

<p align="center">
  <img src="docs/scrawl-voice.gif" alt="Scrawl turning speech into text in a note, live" width="480">
</p>

## Install

Requires macOS 14 or later. Runs best on Apple Silicon.

**Homebrew**

```bash
brew tap jetemple/tap
brew trust jetemple/tap          # trust the third-party tap (one-time)
brew install --cask scrawl
```

Upgrade later with `brew upgrade --cask scrawl`. Whisper models need the `whisper-cpp` binary (`brew install whisper-cpp`); Parakeet v3 on Apple Silicon needs nothing extra.

**Direct download**

Grab `Scrawl-<version>.dmg` from the [latest release](https://github.com/Jetemple/Scrawl/releases/latest), open it, and drag Scrawl to Applications. The app is signed and notarized. Check for new versions any time from the menu bar: Scrawl icon, then "Check for Updates".

**From source**

Needs the Xcode command line tools. Install `whisper-cpp` too if you want Whisper models or bring-your-own ggml models.

```bash
git clone https://github.com/Jetemple/Scrawl.git
cd Scrawl && make install PREFIX=/Applications
open /Applications/Scrawl.app
```

## Usage

Focus a text field, hold Right Option ⌥, speak, and release. Scrawl transcribes on-device and pastes the result at the cursor. Double-tap the hotkey to record hands-free, tap again to stop. Rebind the key in Settings → General.

On first launch, grant Microphone and Accessibility when asked. Scrawl starts with Whisper `small.en` (466 MB), a fast English-only model that needs `whisper-cpp` from Homebrew. On Apple Silicon, the Models menu also offers Parakeet v3: one click, no extra binary, and your current model keeps working until the download finishes. Other Whisper sizes live in the same menu: `medium` (1.5 GB) handles other languages, `large-v3-turbo` (1.6 GB) is the most accurate.

## Features

- **Fully local.** Audio never leaves your Mac.
- **Pastes at the cursor.** Straight into the focused field, or the clipboard if an app blocks it.
- **Parakeet v3 on Apple Silicon.** One-click download, no extra binary.
- **Bring your own Whisper model.** Download a built-in size (tiny/small/medium/large-v3-turbo), or load any whisper.cpp ggml model.
- **Stays warm.** Keeps the model in memory between recordings, unloads it after an idle delay you pick. GPU by default, CPU fallback.
- **Never records forever.** Recordings stop themselves at a limit you set (1 to 10 minutes), so a stuck key can't run your mic all day.
- **Custom vocabulary.** Teach it the names, jargon, and acronyms you use.
- **Local history.** Last 100 transcripts, searchable, on-device. One switch wipes them.
- **Launch at login.** Start Scrawl in the menu bar when you sign in, from Settings → General.

## Bring your own model

If it runs on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and it's a ggml `.bin`, Scrawl loads it: quantized builds, [distil-whisper](https://huggingface.co/distil-whisper), your own fine-tunes.

Add one under **Models** in Settings:

- **Add Model…** imports a `.bin` you've downloaded, after checking it's a real ggml model.
- **Reveal Models Folder** opens the folder so you can drop `ggml-*.bin` files straight in.

[ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/main) on Hugging Face has every size, plus `q5`/`q8` quantized variants. Non-Whisper models won't load.

## Troubleshooting

<details>
<summary>Permissions break after a reinstall or upgrade</summary>

Replacing the app in place (a brew upgrade, or dragging a new copy over the old one) can leave macOS holding a stale Accessibility grant: System Settings shows Scrawl as enabled, but text stops inserting and no permission prompt appears. Open System Settings → Privacy & Security → Accessibility and turn Scrawl off and on.

Source builds are unsigned, so macOS drops the Accessibility grant on every reinstall. Sign with a stable identity to keep it:

```bash
security find-identity -v -p codesigning          # find your identity
SCRAWL_CODESIGN_IDENTITY="Your Name (TeamID)" make install
```

If toggling doesn't fix it, reset the grants and relaunch:

```bash
tccutil reset Microphone com.jetemple.scrawl
tccutil reset Accessibility com.jetemple.scrawl
open /Applications/Scrawl.app
```
</details>

<details>
<summary>Text goes to the clipboard instead of pasting</summary>

Some app has macOS Secure Keyboard Entry on, often a terminal or password manager, which blocks synthesized ⌘V system-wide. Scrawl writes into native text fields through the Accessibility API where it can, and otherwise leaves the text on the clipboard. Press ⌘V to paste, or turn off secure input in the app that switched it on.
</details>

## Development

```bash
make build      # build
make test       # run tests
make lint       # SwiftLint
make format     # apply SwiftFormat (format-check to verify only)
make doctor     # check toolchain and dependencies
make run        # run this source build
make run-debug  # same, plus manual record/stop controls for diagnostics
make clean
make uninstall
```

Environment overrides:

```bash
SCRAWL_WHISPER_EXECUTABLE=/path/to/whisper-cli make run   # custom whisper binary
SCRAWL_MODELS_DIR=/path/to/models make run                # custom models directory
SCRAWL_WHISPER_THREADS=8 make run                         # whisper thread count (default: auto, 4 to 8)
SCRAWL_DISABLE_GPU=1 make run                             # force CPU-only
```

## License

MIT
