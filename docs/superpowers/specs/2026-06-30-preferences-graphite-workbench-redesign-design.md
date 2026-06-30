# Preferences Graphite Workbench Redesign

## Context

Scrawl's current Preferences window is functional, but the pages do not yet feel like a cohesive desktop app. The Models page exposed the problem most clearly: the row content can be aligned correctly while the overall page still feels like a stretched table with too much empty space, heavy borders, and disconnected footer controls.

The redesign direction is based on the selected Source List + Workbench mockup:

- `docs/mockups/preferences-graphite-workbench-source-list.png`

That mockup is a flow reference, not an exact visual target. It captures the useful structure: a sidebar, split model-management sections, inline progress, and bottom actions. It should not be copied literally.

## Goals

- Make Preferences feel cohesive, native, and current without turning it into a dashboard.
- Keep the window recognizably macOS: source-list navigation, AppKit controls, compact settings groups, clear selected state.
- Use a restrained Scrawl identity: graphite sidebar, small SF Symbols, and a quiet coral selected accent.
- Make General the landing page because it answers whether Scrawl is ready to dictate.
- Redesign Models as a low-frequency management surface with split Installed and Available sections.
- Rename Vocabulary to Dictionary and align the workflow around preferred terms.
- Add a lightweight History-to-Dictionary path through `Add Term...`.
- Use rendered AppKit snapshots as the main design feedback loop before declaring visual work done.

## Non-Goals

- Do not redesign the recording overlay in this pass.
- Do not add broad model metadata, ranking, filtering, or search unless the current data actually needs it.
- Do not implement replacement rules such as `wrong -> correct` unless the transcription pipeline consumes them.
- Do not add AI-mode prompts, per-app profiles, or advanced assistant configuration.
- Do not make Preferences look like a web admin panel or SaaS dashboard.

## Visual Direction

The direction is **Graphite Workbench**.

The shell should feel custom but quiet. The sidebar can be graphite and branded, but the content area stays light, native, and utilitarian. The app should read as a polished Mac utility rather than a generated AI tool.

Keep from the selected mockup:

- Left source-list navigation.
- Stronger Models information architecture.
- Split `Installed Models` and `Available Downloads`.
- Inline download progress.
- Pinned bottom actions for management pages.
- Compact, repeated row structure.

Reject from the selected mockup:

- Search on Models.
- Repeated cube icons in model rows.
- Kebab menus without real hidden actions.
- Visible table column headers for model rows.
- Heavy SaaS-style sidebar item treatment.
- Template sections such as Recording, Audio, Appearance, Advanced, and Updates.
- Oversized window title treatment and overly broad preferences taxonomy.

## Navigation

Preferences should use these sections:

- `General`
- `Models`
- `Input`
- `History`
- `Dictionary`
- `About`

`General` opens first.

`Keyboard` becomes `Input` because the page can contain hotkey and input/permission-related controls as the product grows. `Vocabulary` becomes `Dictionary` because preferred terms are the clearer product model and match competitor language.

## Shared Shell

The window remains a sidebar/content preferences window.

Sidebar requirements:

- Custom graphite sidebar, not a full dark dashboard.
- Real Scrawl sections only.
- Smaller SF Symbols aligned to labels.
- Restrained selected state: subtle rounded selection fill or sidebar accent, plus coral tint.
- No row glow, oversized icons, decorative meters, or generated-looking row art.

Content requirements:

- Light native background.
- Page headers should be compact and factual.
- Page descriptions should be short and used only where they clarify the page.
- Groups should use native rounded surfaces and subtle separators.
- Workbench pages can use pinned bottom action bars.
- Settings pages should keep controls close to their labels and avoid empty table-like regions.

## General Page

General is the landing page and should answer: is Scrawl ready, and how will it behave?

Content:

- Readiness status.
- Current model summary with a `Change...` action that opens or selects the Models page.
- Current hotkey summary.
- Microphone permission status and action.
- Accessibility permission status and action.
- Model offload policy.
- Clipboard history setting.
- Launch at login setting.

Layout:

- Use compact grouped settings.
- Do not make it a dashboard.
- The current model summary should be visible without making model management live on General.

## Models Page

Models is a management page, not the Preferences landing page.

Content structure:

- `Installed Models`
- `Available Downloads`
- Pinned bottom action bar.

Model rows:

- Native list-like rows, not a visible web table.
- No search field.
- No cube icons.
- No visible column headers.
- Left side: model name and short description.
- Right side: status text, optional progress, action button, and an `info.circle` details button.
- Selected/current model state should be visible but restrained.
- Download progress should be inline and include a slim progress bar when a download is active.
- Details should open in a popover anchored to `info.circle`.

Bottom action bar:

- Left side: `Add Model...`, `Reveal Models Folder`.
- Right side: contextual actions such as `Cancel Download` or `Delete Selected` when applicable.
- Actions should stay fixed at the bottom of the page so the layout does not jump when lists are short.

Details popover:

- Keep it short.
- Use it for size, engine family, installed path or source, and any future details.
- Do not permanently reserve a right-side inspector for low-frequency metadata.

## Input Page

Input replaces Keyboard.

Initial content:

- Current hotkey.
- `Set Hotkey...` or equivalent capture action.

Possible future content:

- Microphone input behavior if it becomes configurable.
- Permission-related affordances if General becomes too dense.

For this redesign, Input can remain simple. Do not invent new settings.

## History Page

History remains a workbench page for transcript records.

Content:

- Transcript history enablement control.
- Search transcripts.
- Transcript list.
- Pinned bottom action bar.

Rows:

- Keep transcript text first.
- Use secondary metadata for timestamp and metrics.
- Keep rows clean. Do not reveal inline row buttons by default.

Bottom action bar:

- `Copy`
- `Paste Again`
- `Add Term...`
- trailing destructive `Delete`

`Add Term...`:

- Adds a preferred dictionary term from history context.
- It should not be labeled `Correct...` for now.
- It should not imply `heard -> correct` replacement behavior.
- The first implementation should open a small popover anchored to the action with one main field: `Preferred term`.
- Saving adds the term to Dictionary.

## Dictionary Page

Dictionary replaces Vocabulary.

Purpose:

- Manage preferred words, names, phrases, acronyms, company names, and technical terms.

Content:

- Add preferred term field.
- Search terms when terms exist.
- Preferred terms list.
- Pinned bottom action bar with edit/delete/recover where applicable.

Scope:

- Keep it as a simple preferred-terms list for v1.
- Do not add categories such as Names, Companies, Acronyms, or Technical Terms unless the engine uses them differently.
- Do not expose replacement rules until post-processing supports them.

## About Page

About remains simple:

- App version.
- Privacy note.
- Project link.

It should inherit the shared shell and grouped setting style, but does not need workbench treatment.

## Behavior And Data Flow

No model-management behavior changes are required by the redesign.

Expected navigation additions:

- `General` current-model `Change...` selects Models.
- `History` `Add Term...` saves through the existing dictionary save path.

Expected naming changes:

- `Keyboard` section title becomes `Input`.
- `Vocabulary` section title becomes `Dictionary`.
- Vocabulary internals can remain backed by the existing dictionary store.

## Components

Likely shared components:

- Graphite sidebar row.
- Page shell/header helper.
- Native grouped row/list helper.
- Pinned bottom action bar helper.
- Workbench empty-state helper.

Likely page-specific components:

- Model section list rows.
- Model details popover.
- History preferred-term popover.
- Dictionary row/list controls.

The implementation should avoid a broad theme framework unless repeated constants become hard to manage.

## Testing And Verification

The redesign should be verified with rendered AppKit snapshots, not only constraint-level tests.

Add or extend snapshot coverage for:

- Full Preferences shell on General.
- Models installed state.
- Models downloading state.
- Models minimum width.
- History with records.
- Dictionary with terms.

Programmatic layout tests should cover:

- Critical controls stay within bounds at minimum window size.
- Sidebar sections match the expected titles.
- General opens first.
- `Change...` selects Models.
- Models rows do not expose table headers, search, or unnecessary overflow actions.
- Selected/current model rows do not show a `Use` action for the current model.
- History action bar fits at minimum width.
- Dictionary is used as the visible section title instead of Vocabulary.

Manual visual review should compare generated snapshots against the selected mockup direction while explicitly checking that the rejected mockup artifacts were not copied.

## Risks

- The graphite sidebar can become too heavy. Keep it quiet and native.
- Splitting Models can make the page taller. Use compact native rows and avoid search/header chrome.
- The History `Add Term...` workflow can overpromise correction behavior. Keep language tied to preferred terms only.
- Pinned bottom bars can feel too app-like if used everywhere. Limit them to Models, History, and Dictionary.
- The implementation can drift into unrelated feature work. Keep the first pass focused on navigation, layout, visual cohesion, and the preferred-term workflow.
