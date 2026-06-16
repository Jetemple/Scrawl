# Graphite Native Redesign

## Context

Scrawl is a native macOS menu bar app for local voice-to-text. The existing app icon is a charcoal rounded slab with a coral waveform. The current in-flight visual directions felt off:

- Inkwell had useful depth, but read like a standard cloud-code UI.
- Aurora had energy, but also felt generic.
- Scrawl felt old.
- Rizzo felt too goofy.

The approved direction is **Graphite Native**: expand the current logo into the app UI without turning the preferences window into a themed dashboard.

## Goals

- Make the recording overlay pill feel intentional, branded, and aligned with the app icon.
- Keep the preferences window readable and recognizably native.
- Use graphite and coral as the core identity system.
- Avoid generic SaaS/cloud-code patterns, neon signal dashboards, beige studio hardware, and playful mascot energy.
- Preserve existing behavior, accessibility announcements, resizing behavior, and Reduce Motion handling.

## Non-Goals

- No app rename or logo redesign.
- No large navigation or settings architecture changes.
- No new recording behavior.
- No decorative meters across the settings UI.
- No wholesale custom control framework.

## Visual System

The UI should inherit from the app icon:

- **Graphite:** near-black surfaces for identity moments.
- **Coral:** primary brand and recording accent, matching the waveform in the app icon.
- **Rounded slab geometry:** softer, compact rounded forms that echo the icon shape.
- **Native content:** light macOS-style settings content for readability.

Teal, neon green, beige hardware palettes, and broad gradients are out of scope for the final direction.

## Recording Overlay Pill

The pill is the primary redesign surface.

Use the **Logo Slab** direction:

- Graphite rounded slab shell.
- Coral recording dot.
- Compact coral waveform mark when the state is recording.
- Clear state label.
- Subtle border and shadow.
- Compact width that does not feel busy during repeated dictation.

### State Treatment

**Recording**

- Graphite shell.
- Coral dot with restrained glow or pulse.
- Label: `Recording`.
- Small coral waveform at the trailing edge.
- Motion must respect Reduce Motion. If Reduce Motion is enabled, keep the dot and waveform static.

**Transcribing**

- Same graphite shell.
- No red recording dot.
- Use the existing spinner or a subtle waveform shimmer if it can be implemented cleanly.
- Label: `Transcribing`.

**Hotkey Capture**

- Same graphite shell.
- Keyboard icon in coral.
- Label: `Press Hotkey`.

**Transient Messages**

- Same graphite shell.
- No waveform unless the message is directly recording-related.
- Continue to support longer messages with existing width and two-line wrapping behavior.

### Pill Fallback

If the waveform makes the AppKit pill too wide, visually busy, or brittle with dynamic text, fall back to the logo-slab shell with dot/icon-only state indicators. The shell, graphite palette, coral accent, and improved typography are the required parts.

## Preferences Window

Settings should support the brand, not compete with the pill.

- Keep the existing sidebar/content layout.
- Make the sidebar graphite.
- Use coral for the selected section state.
- Add a small logo or waveform identity treatment in the sidebar header.
- Keep content panels light and native.
- Tighten spacing where it improves scanability.
- Use 10-12px rounded groups where practical.
- Do not add decorative waveform or meter elements throughout every page.

## Components and Code Boundaries

Primary files likely involved:

- `Sources/RecordingOverlay/RecordingOverlayController.swift`
- `Sources/AppUI/PreferencesWindowController.swift`
- `Sources/AppUI/PreferencesPageSupport.swift`

Possible helper:

- A small waveform drawing view/helper local to the overlay implementation, only if it keeps the pill code readable.

Do not introduce a broad theming system unless the implementation shows repeated color/layout constants becoming hard to maintain.

## Behavior and Accessibility

Existing behavior must remain intact:

- Overlay states: idle, hotkey capture, recording, transcribing.
- Transient messages.
- Fade in/out behavior.
- Dynamic pill width and height.
- Two-line message wrapping.
- VoiceOver announcements for non-idle states.
- Reduce Motion behavior for pulse or shimmer effects.
- Mouse-transparent, non-activating panel behavior.

## Testing

Update or add tests around behavior that changes:

- Pill width and height calculations still handle labels with and without leading/trailing accessories.
- Long transient messages still wrap or truncate cleanly.
- Existing overlay size tests continue to pass.
- Preferences layout tests continue to pass after sidebar/content styling changes.

Manual verification:

- Preview recording, transcribing, hotkey capture, and transient message states.
- Check light and dark macOS appearances if practical.
- Check Reduce Motion behavior.
- Confirm the pill does not feel too wide or busy with the waveform enabled.

## Implementation Priority

1. Redesign `RecordingOverlayController` around the logo-slab pill.
2. Add a small waveform view/helper only if it stays clean and stable.
3. Apply restrained Graphite Native styling to the preferences sidebar and shared group surfaces.
4. Run tests and manually inspect the overlay states.

The pill is the success criterion. Preferences styling is secondary polish.
