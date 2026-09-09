# Contributing to Scrawl

Thanks for helping make local dictation better. Scrawl is a macOS app, so contributions should preserve its local-first, privacy-conscious design.

## Before opening a pull request

Run the checks that apply to your change:

```bash
swift test
make format-check
make lint
ruby scripts/update-homebrew-cask_test.rb
```

For UI changes, include screenshots or a short recording when that makes the change easier to review. Do not include transcripts, recordings, model files, or other private data in commits or issue attachments.

## Pull requests

- Keep each pull request focused on one problem.
- Explain the user-facing behavior and how you verified it.
- Add or update tests for behavior changes.
- Call out changes to permissions, model downloads, release artifacts, or persisted settings.
- Do not commit credentials, signing certificates, API tokens, audio, or generated build output.

Release preparation is intentionally separate from ordinary feature work. See [`RELEASE.md`](RELEASE.md) for the version-bump and notarization process.
