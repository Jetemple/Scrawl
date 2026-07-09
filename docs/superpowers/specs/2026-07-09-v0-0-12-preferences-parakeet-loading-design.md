# v0.0.12 Preferences and Parakeet Loading Polish

## Summary

v0.0.12 should keep the current native AppKit preferences design, but finish two visible polish gaps:

1. Make secondary buttons in Preferences behave consistently with the new press-down feedback.
2. Make Parakeet setup feel like a first-class loading state in Models and during attempted dictation.

This is not a full preferences redesign. The goal is to improve feedback, consistency, and trust without changing the existing information architecture.

## Goals

- Apply the same secondary button press feedback across Preferences pages.
- Remove the global negative tracking tweak from Preferences page titles unless snapshot review proves it is better.
- Show Parakeet setup phases clearly:
  - `Loading Parakeet...`
  - `Downloading Parakeet model - 42%`
  - `Optimizing Parakeet for your Mac...`
- Reuse the Models page progress treatment for Parakeet download progress.
- Show a subtle non-percent activity indicator for checking-cache and optimizing phases.
- If dictation is attempted while Parakeet is preparing, show a visible overlay message instead of leaving the user to infer state from the menu.

## Non-Goals

- No new preferences navigation.
- No glass/material redesign of the preferences window.
- No new Parakeet download manager.
- No change to model selection semantics.
- No change to the audio hallucination gate work already in progress.

## Existing Context

- `PreferencesPageSupport.makeSecondaryButton` creates `PressFeedbackButton`, but only General currently uses it.
- Other Preferences pages still instantiate plain `NSButton` and call `configureSecondaryButton`.
- `ParakeetPreparationState` already models checking-cache, downloading, optimizing, ready, and failed states.
- `ScrawlApplication.startSelectedModelPreparationIfNeeded()` already starts preparation for selected Parakeet models and publishes progress.
- `PreferencesModelRow` already has `isPreparing` and `downloadProgressText`.
- `PreferencesModelsView` already has a mini progress bar, but currently renders it only when `row.isDownloading`.

## Approach

### Preferences Button Consistency

Use `PreferencesPageSupport.makeSecondaryButton` for secondary command buttons across:

- General
- Models
- History
- Dictionary
- About

Leave checkboxes, pop-up buttons, search fields, table rows, and active markers as native controls.

The factory remains responsible for shared secondary-button style and press feedback. Call sites should not call `configureSecondaryButton` again after using the factory.

### Preferences Typography

Remove the always-on page title `kern` adjustment from `PreferencesPageSupport.makePageHeader`.

The existing page title size is system UI scale, not display scale. Keeping system default tracking is the safer native AppKit choice unless snapshot review shows a clear regression.

Keep the body leading adjustment only if snapshots still look better and all page headers remain within layout bounds.

### Parakeet Models Row

For rows where `row.isPreparing` is true:

- Status text should use the Parakeet phase label when available.
- Downloading phase with a percent should show the same mini progress bar as model downloads.
- Checking-cache and optimizing phases should show a small indeterminate activity indicator or subtle pulsing status dot.
- The action column should show disabled `Preparing`, using the same button style as other secondary buttons for visual consistency.
- Reduced Motion should avoid any pulsing animation; use a static indicator or native indeterminate progress control instead.

The Models page should not move Parakeet into a separate special section. It should remain in the same installed/available model row system.

### Dictation Attempt While Preparing

When `ParakeetDictationReadiness.evaluate` returns not ready, the app should show the existing message in the overlay:

`Parakeet is still setting up`

The status/menu can keep the longer guidance:

`Parakeet is still setting up. Pick another model to use now, or wait a moment.`

This keeps the overlay short enough for the recording pill while preserving detail in the menu/status path.

## Data Flow

1. `ScrawlApplication` starts Parakeet preparation after model selection or launch when Parakeet is selected.
2. The provider emits `ModelPreparationProgress`.
3. `ParakeetPreparationState` converts provider progress into phase labels and optional download fraction.
4. `ModelCatalog` exposes that progress through `ManagedModelPreparationProgress`.
5. `PreferencesModelState.rows` maps progress into `PreferencesModelRow`.
6. `PreferencesModelsView` renders the row text, progress bar, and activity indicator.
7. Dictation readiness checks use the same preparation state and show overlay guidance when needed.

## Error Handling

- Existing Parakeet setup failure behavior remains:
  - mark preparation failed
  - show setup failure dialog
  - refresh Preferences
  - allow fallback to Whisper
- Progress rendering must fail soft:
  - nil fraction means show indeterminate state, not `0%`
  - stale progress should not regress the displayed percent
  - ready state should clear the progress row and return to installed/recommended state

## Testing

Add or update focused tests:

- `PreferencesPageSupport.makeSecondaryButton` returns a `PressFeedbackButton`.
- Models, History, Dictionary, About, and General use the shared secondary button where appropriate.
- Parakeet preparing rows show:
  - checking/loading label
  - downloading label and mini progress bar
  - optimizing label
  - disabled `Preparing` action
- Dictation attempt while Parakeet is preparing shows the short overlay message.
- Existing snapshot tests should still pass; optional snapshot artifact generation can be used for visual review.

## Acceptance Criteria

- Preferences secondary buttons have consistent press feedback across pages.
- Preferences headers remain native-looking and do not use global negative tracking by default.
- Parakeet setup is visible in the Models row with clear phase labels.
- Percent download progress for Parakeet shows a progress bar.
- Non-percent Parakeet phases show visible activity, not a dead disabled row.
- Reduced Motion users do not get pulsing or looping decorative motion in the Models row.
- Attempting dictation during setup produces clear overlay feedback.
- Full test suite passes.
