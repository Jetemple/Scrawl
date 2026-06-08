# History Row Cleanup Design

## Goal

Make transcript history read like saved content rather than transcription debug logs.

## Changes

- Put transcript text first in each history row.
- Explicitly left-align transcript text.
- Move date and performance details into a quiet footer below the transcript.
- Show only audio duration and processing duration in the visible footer.
- Remove visible word count and WPM from history rows.
- Preserve selection, copy, paste-again, delete, search, and storage behavior.

## Testing

- Update history metric formatting tests.
- Add a row-presentation regression test.
- Inspect the rendered History page with real records.
- Run the full Swift test suite.
