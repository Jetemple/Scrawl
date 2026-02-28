# Publish v0.0.2 (GitHub)

This is a simple path to publish Scrawl as a source-first project.

## 1. Final local check

```bash
swift test
swift run ScrawlApp
```

Verify:

- Microphone permission works
- Accessibility permission works
- Hold-to-talk works
- Transcript pastes into a focused text field

## 2. Initialize git and first commit

```bash
git init
git add .
git commit -m "Public release v0.0.2"
```

## 3. Create GitHub repo and push

```bash
git branch -M main
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin main
```

## 4. Tag v0.0.2

```bash
git tag -a v0.0.2 -m "Scrawl v0.0.2"
git push origin v0.0.2
```

## 5. (Optional) GitHub Release notes

- What already works (hotkey dictation, local whisper.cpp, model menu, dictionary learn)
- What’s still rough (menu-first settings, no packaged app yet)
- What’s next (`.app` packaging, then Homebrew cask)
