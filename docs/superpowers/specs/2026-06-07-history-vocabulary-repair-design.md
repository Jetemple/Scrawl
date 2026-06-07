# History and Vocabulary Repair Design

## Summary

Repair the current sidebar-settings feature around Scrawl's core job:

- Keep recording controlled by the configured hotkey.
- Present History as a compact chronological transcript feed.
- Replace correction-pair Dictionary behavior with a preferred-terms Vocabulary list.
- Pass Vocabulary terms to `whisper-cli` as initial prompt context.
- Make local development launches unambiguous so an installed Scrawl binary cannot silently be mistaken for the current source build.

This pass removes unnecessary History-to-Dictionary interactions and does not add transcript editing.

## Recording Workflow

The configured hotkey remains the primary recording interaction:

- Hold to record and release to transcribe.
- Double-tap to lock recording.
- Tap again to stop and transcribe.

Debug-only manual recording actions must not be presented as the normal workflow. Local-run documentation must use a non-debug launch by default.

## History

### Layout

History becomes a compact, single-column chronological feed. Records are grouped by day and shown newest first. Each entry displays the transcript at readable width without requiring a separate detail pane.

The page contains:

- Page title and short local-storage description
- `Save transcript history` privacy control
- Search field
- Chronological transcript feed

Each transcript supports only:

- Copy
- Paste Again
- Delete

History does not expose text-selection actions, correction actions, or Vocabulary actions.

### Metrics

Each new History record stores:

- Stable UUID
- Creation date
- Transcript text
- Recording duration in milliseconds
- Transcription latency in milliseconds

Each feed entry quietly displays:

- Word count
- Recording duration
- Speaking rate in words per minute
- Transcription duration

Speaking rate is calculated from word count and recording duration. If a legacy record does not contain timing metadata, unavailable metrics are omitted rather than fabricated.

Existing History JSON remains readable by making timing fields optional during decoding.

## Vocabulary

### User Model

Rename the user-facing Dictionary section to `Vocabulary`.

Vocabulary is a searchable list of preferred names, technical terms, and phrases, for example:

- Anduril
- Postgres
- Kubernetes

Users can:

- Add a preferred term
- Search terms
- Edit a term
- Delete one or multiple terms

The UI does not show correction pairs, arrows, `heard text`, or replacement fields.

### Storage and Migration

Vocabulary remains local JSON storage in Scrawl's Application Support directory.

Existing dictionary entries migrate by retaining each entry's corrected value as a preferred term. Terms are trimmed, empty terms are removed, and duplicates are removed case-insensitively while preserving order.

The storage API exposes explicit preferred-term operations rather than replacement operations. Runtime transcription no longer applies post-transcription string replacement.

### Whisper Prompt Context

Before transcription, Scrawl reads preferred Vocabulary terms and adds them to the transcription request as prompt context.

`WhisperCppProvider` passes non-empty prompt context to `whisper-cli` using:

```text
--prompt "Preferred vocabulary: Anduril, Postgres, Kubernetes"
```

Prompt context improves recognition but does not guarantee a term will be used. The UI describes Vocabulary accordingly.

Prompt construction is deterministic, case-insensitively deduplicated, and bounded to avoid oversized command arguments.

## Local Development Launch

Add a documented development launch command that:

1. Detects an already-running installed Scrawl instance.
2. Stops it before launching the current source build.
3. Launches without `SCRAWL_DEBUG=1`.

Debug launch remains available as a separate explicit command.

The normal local-run documentation must explain that Control-R and Control-S are debug-only manual actions, not Scrawl's configured hotkey.

## Architecture

- `TranscriptHistoryStore` owns persisted History timing metadata and legacy decoding.
- `AudioCapture` returns recording duration with the captured audio URL.
- `TranscriptionCore` carries optional prompt context.
- `WhisperCppProvider` translates prompt context to the supported `--prompt` CLI argument.
- The existing `DictionaryStore` module is converted internally to preferred-term Vocabulary storage while preserving legacy JSON migration.
- `StatusBarAppDelegate` supplies Vocabulary prompt context and saves History metrics.
- `PreferencesHistoryView` renders the compact feed.
- `PreferencesDictionaryView` is replaced by a user-facing `PreferencesVocabularyView`.

## Error Handling

- Failed Vocabulary persistence remains visible and does not update the displayed list falsely.
- Missing or malformed legacy Vocabulary data produces an empty list without crashing.
- History records without timing metadata render normally with only available metrics.
- Prompt context failure cannot prevent transcription; an empty prompt is equivalent to no Vocabulary.

## Testing

Automated tests cover:

- Legacy dictionary-pair migration to preferred terms
- Preferred-term add, edit, delete, deduplication, and persistence
- Prompt construction and `--prompt` CLI arguments
- Transcription request prompt context
- History timing metadata persistence and legacy decoding
- WPM and metric formatting
- Compact History feed layout at default and minimum window sizes
- Vocabulary filtering and selection
- Local-run script behavior where practical

Final verification runs:

```bash
swift test
swift build -c release --product ScrawlApp
git diff --check
```

Manual verification covers configured-hotkey recording, Vocabulary term recognition, History feed readability, metrics, privacy controls, and local launch behavior.

## Out of Scope

- Editing old transcript text
- Automatically learning Vocabulary from user corrections
- Guaranteed term replacement
- Cloud or synced Vocabulary
- Wispr Flow-inspired settings such as launch at login, sound controls, smart formatting, creator mode, or reset-all-data
