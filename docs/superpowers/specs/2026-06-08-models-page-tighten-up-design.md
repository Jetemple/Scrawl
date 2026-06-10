# Models Page Tighten-Up Design

## Goal

Make the Models page easy to scan and visually consistent with the rest of Settings.

## Changes

- Keep the existing page header, rounded list group, model actions, and delete action.
- Anchor model rows to the top of the list instead of the bottom.
- Render every model as a compact two-line row:
  - First line: model name on the left; status and action on the right.
  - Second line: model description and download size in secondary text.
- Show the selected model with a checkmark and selected status instead of a disabled duplicate button.
- Keep installed and downloadable model actions aligned to a fixed trailing column.
- Keep separators between rows and the delete action in the existing footer.

## Behavior

No model selection, download, deletion, or persistence behavior changes.

## Testing

- Add layout assertions for top-anchored, two-line model rows.
- Preserve existing minimum-size and action tests.
- Run the full Swift test suite and inspect the rendered Models page.
