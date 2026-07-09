# v0.0.12 Preferences and Parakeet Loading Polish

## Summary

v0.0.12 should keep Scrawl's current native AppKit preferences design and finish the remaining visible polish gaps:

1. Make secondary buttons in Preferences use one shared press-feedback path.
2. Render the existing Parakeet preparation state properly in the Models row.
3. Remove the page-title tracking tweak unless snapshot review proves it is better.

This is not a full preferences redesign and not a rewrite of Parakeet preparation. The upstream Parakeet state, phase labels, progress mapping, and dictation readiness checks already exist.

## Goals

- Route Preferences secondary command buttons through `PreferencesPageSupport.makeSecondaryButton`.
- Remove redundant `configureSecondaryButton` calls after a button has already come from the factory.
- Remove the always-on negative `kern` from Preferences page titles by default.
- In Models, render `row.isPreparing` as a first-class row state:
  - existing phase text remains the source of truth
  - download percent gets the mini progress bar
  - checking-cache and optimizing phases show visible non-percent activity
  - the action column shows a disabled `Preparing` control
- Keep the current Parakeet setup flow, progress state, and model-selection semantics.
- Optionally split dictation readiness copy into a short overlay message and a longer status/menu message.

## Non-Goals

- No new preferences navigation.
- No glass/material redesign of the preferences window.
- No new Parakeet download manager.
- No changes to provider progress mapping.
- No changes to the audio hallucination gate work already in progress.
- No special Parakeet-only section in Models.

## Verified Existing Context

Already implemented:

- `ParakeetPreparationState.label(for:includePercent:)` emits the phase labels:
  - `Loading Parakeet…`
  - `Downloading Parakeet model — 42%`
  - `Optimizing Parakeet for your Mac…`
- `ScrawlApplication.startSelectedModelPreparationIfNeeded()` starts preparation and publishes progress.
- `ParakeetDictationReadiness.evaluate` blocks dictation while Parakeet is preparing.
- `ScrawlApplication.validateTranscriptionPrerequisites` already shows the readiness message in the overlay and status.
- `PreferencesModelRow` already has `isPreparing`, `downloadProgressText`, and `actionTitle == "Preparing"` for preparing rows.
- `PreferencesModelsView` already has `MiniProgressBar`.

Still missing or inconsistent:

- `PreferencesModelsView.makeStatusCell` gates the headline, status-dot suppression, and mini progress bar on `row.isDownloading`, so preparing rows do not get the richer visual treatment.
- `PreferencesModelsView.makeActionCell` uses its local `actionButtonTitle(_:)`, which only knows `Cancel`, `Use`, and `Download`; it ignores `row.actionTitle`.
- General currently uses `makeSecondaryButton` and then redundantly calls `configureSecondaryButton`.
- Models, History, Dictionary, and About still create plain `NSButton` instances for secondary command buttons.
- Preferences page titles currently get an unconditional negative `kern`.

## Approach

### Preferences Button Consistency

Use `PreferencesPageSupport.makeSecondaryButton` for secondary command buttons across:

- General
- Models
- History
- Dictionary
- About

Leave checkboxes, pop-up buttons, search fields, table rows, and active markers as native controls.

The factory owns shared secondary-button style and press feedback. Call sites should not call `configureSecondaryButton` after using the factory.

### Preferences Typography

Remove the always-on page-title `kern` adjustment from `PreferencesPageSupport.makePageHeader`.

The page title size is system UI scale, not display scale. Keeping system default tracking is the safer native AppKit choice unless generated snapshots prove otherwise.

Keep the body leading adjustment only if snapshots still look better and all page headers remain within layout bounds.

### Parakeet Models Row

For rows where `row.isPreparing` is true:

- Use `row.statusText` for the headline. Do not duplicate Parakeet phase-label logic in the view.
- If `row.downloadProgressText` contains a percent, show the same `MiniProgressBar` used for downloading rows.
- For non-percent phases, show visible activity without implying a percent:
  - preferred: native small indeterminate progress control, if it fits the row cleanly
  - acceptable: static status dot for Reduce Motion plus subtle pulsing dot when motion is allowed
- Use `row.actionTitle` for the action button title, so preparing rows show `Preparing`.
- Disable the preparing action, because there is no user action to take while setup is running.

The Models page should keep Parakeet in the normal model row system.

### Dictation Attempt While Preparing

The current behavior already shows the readiness message in the overlay and status. The only optional polish is copy splitting:

- overlay pill: `Parakeet is still setting up`
- status/menu: `Parakeet is still setting up. Pick another model to use now, or wait a moment.`

This should be treated as optional because the behavior is already present.

## Data Flow

1. `ScrawlApplication` starts Parakeet preparation after launch or model selection when Parakeet is selected.
2. The provider emits `ModelPreparationProgress`.
3. `ParakeetPreparationState` converts provider progress into existing phase labels and optional download fraction.
4. `ModelCatalog` exposes preparation progress through `ManagedModelPreparationProgress`.
5. `PreferencesModelState.rows` maps progress into `PreferencesModelRow`.
6. `PreferencesModelsView` renders preparing rows using the row's existing text and action fields.

## Error Handling

- Existing Parakeet setup failure behavior remains:
  - mark preparation failed
  - show setup failure dialog
  - refresh Preferences
  - allow fallback to Whisper
- Progress rendering must fail soft:
  - nil fraction means show indeterminate activity, not `0%`
  - stale progress should not regress the displayed percent
  - ready state should clear the progress row and return to installed/recommended state

## Testing

Add or update focused tests:

- `PreferencesPageSupport.makeSecondaryButton` returns a `PressFeedbackButton`.
- General does not re-run `configureSecondaryButton` after using the factory.
- Models, History, Dictionary, and About use the shared secondary button where appropriate.
- Preparing Parakeet rows show:
  - existing loading/checking label
  - existing download label plus mini progress bar when percent is available
  - existing optimizing label
  - disabled `Preparing` action from `row.actionTitle`
- Existing dictation-readiness overlay behavior remains covered; add copy-split coverage only if that optional polish is implemented.
- Existing snapshot tests should still pass; optional snapshot artifact generation can be used for visual review.

## Acceptance Criteria

- Preferences secondary buttons have consistent press feedback across pages.
- Preferences call sites do not double-configure buttons created by `makeSecondaryButton`.
- Preferences headers remain native-looking and do not use global negative tracking by default.
- Parakeet setup remains driven by the existing preparation state and labels.
- Preparing Parakeet rows show visible activity instead of a dead disabled row.
- Percent Parakeet preparation progress shows a mini progress bar.
- The preparing action button reads `Preparing` and is disabled.
- Reduced Motion users do not get pulsing or looping decorative motion in the Models row.
- Full test suite passes.
