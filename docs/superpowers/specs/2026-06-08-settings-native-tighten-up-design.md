# Settings Native Tighten-Up Design

## Goal

Make the existing Settings window feel deliberate and consistent without redesigning it or changing behavior.

## Scope

- Preserve the current sidebar navigation, page names, window size, and all existing actions.
- Standardize page margins, header spacing, group spacing, row padding, button placement, and typography.
- Make History and Vocabulary visually match General, Models, Keyboard, and About.
- Use restrained native macOS styling throughout.
- Leave the menu-bar dropdown and recording overlay unchanged.

## Visual System

- Every page uses the shared page inset: 28 points horizontally and 24 points vertically.
- Every page uses the shared page header and a consistent 16-point gap between major sections.
- Related settings and list workspaces use the same rounded, bordered group background.
- Controls inside groups use consistent 14-point horizontal padding and compact vertical padding.
- Primary page actions sit inside the relevant group or align with its leading edge.
- Destructive actions remain red, but do not receive extra visual emphasis.
- Empty states remain centered within their list workspace.

## Page Changes

### General, Keyboard, and About

Keep their current structure. Normalize multiline detail behavior and spacing through shared helpers.

### Models

Keep the model list and delete action. Place the action in a consistent footer area aligned with the list group.

### History

Use the shared page container instead of custom margins.

Place the enable toggle and search control above a rounded list workspace. Keep transcript rows readable with consistent insets and separators. Keep Copy, Paste Again, and Delete in a compact footer aligned with the workspace.

### Vocabulary

Use the shared page container instead of custom margins.

Keep the add-term row and search control above a rounded list workspace. Keep Edit and Delete in a compact footer aligned with the workspace.

## Architecture

Extend `PreferencesPageSupport` only where a shared helper removes real duplication:

- Shared page inset and spacing constants.
- Shared rounded workspace construction for scroll views and empty states.
- Shared compact action-row construction.

Page-specific behavior remains in each page view. No persistence, action, or data-flow changes are required.

## Error Handling

Existing alerts and empty/error states remain unchanged. The cleanup only changes their layout and presentation.

## Testing

- Preserve existing action and state tests.
- Add layout assertions for the tightened History and Vocabulary workspaces where practical.
- Run the full Swift test suite.
- Launch the app and inspect every Settings page at the default and minimum window sizes.

## Non-Goals

- No new settings or feature behavior.
- No custom theme or dashboard cards.
- No menu-bar dropdown cleanup in this pass.
- No recording overlay changes.
