# Models Preferences Tight Visual Polish Design

## Goal

Polish the Models page in Preferences without changing the workflow or model-management behavior. The page should look cleaner at the default and minimum window sizes while preserving the current one-list structure and existing actions.

## Scope

In scope:

- Keep one rounded list of model rows.
- Keep the existing row actions: select installed models, download missing models, show selected state.
- Keep the existing lower controls: Add Model, Reveal Models Folder, Delete Selected, Cancel Download, and Find Models.
- Improve row alignment, spacing, and hierarchy.
- Improve status/action sizing so longer statuses and progress text do not look cramped.
- Keep the page clean at the existing minimum window size of 620 by 400.
- Add focused layout regression coverage where practical.

Out of scope:

- Splitting installed and available models into separate sections.
- Changing model ordering, selection behavior, download behavior, deletion behavior, or copy.
- Adding new settings or model metadata.

## Design

The implementation will stay inside `PreferencesModelsView` unless a small shared helper in `PreferencesPageSupport` is clearly useful. Rows will remain two-line AppKit stack views, but their internal spacing and sizing will be tightened:

- Model name and description stay left-aligned and truncate before forcing status/action controls off layout.
- Status text keeps required horizontal sizing only where it protects important strings from clipping.
- The selected checkmark is sized to visually occupy the same action slot as row buttons.
- Row insets and vertical spacing are tuned so the list feels compact but not crowded.
- The lower button row remains a single control strip, with spacing and compression behavior adjusted to avoid visual crowding when Cancel Download appears.

The polish should be conservative. If a proposed layout change starts to imply a new workflow or page structure, it should be left out of this pass.

## States To Preserve

- Empty list shows the existing empty state.
- Installed unselected rows show `Installed` plus a `Use` action.
- Selected installed rows show status text plus the selected checkmark.
- Downloadable rows show `Not installed` plus `Download`.
- Downloading rows show progress text when available and disable conflicting downloads.
- Cancelled rows show `Download cancelled` without truncation and remain downloadable.
- Preparing rows keep their current disabled action and preparation status.

## Testing

Run focused App UI tests for model preferences after implementation:

- `PreferencesModelsViewTests`
- Relevant `PreferencesWindowControllerTests`
- Any touched model-state tests if row-state assumptions change

Add or adjust tests for visual regressions that can be asserted programmatically, especially:

- Long status text is not truncated.
- Critical controls fit within the page at minimum size.
- Selected rows do not expose an action button.
- The selected indicator stays in the action slot.

## Risks

The main risk is over-polishing into a larger layout redesign. The implementation should prefer small AppKit layout adjustments over new abstractions. Another risk is making text fit at one width while crowding it at the minimum window size; minimum-size layout tests should catch that.
