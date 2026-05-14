# Cue Inspector Playhead Clock — Design

**Status:** Approved
**Date:** 2026-05-14
**Related:** Inspired by the prominent inspector clock in the Cue Points app.

## Goal

Add an always-visible, large playhead-time readout pinned to the top of the Cue Inspector pane, giving the user the same at-a-glance time reference they get in Cue Points without having to look at the transport bar.

## Non-goals

- No SMPTE / LTC frame display.
- No click-to-seek or editable input.
- No format toggle.
- No tinting or animation tied to play/pause state.

## User-visible behavior

- A large, monospaced-digit time readout sits at the top of the Cue Inspector pane, above the field stack.
- The readout shows the live transport playhead in `HH:MM:SS.mmm` format (e.g., `00:01:23.450`), matching the transport bar's value.
- It ticks in real time during playback and updates from drags / seeks.
- It is visible in both states of the inspector: when a cue is selected **and** when the empty state ("Select a cue") is shown. In the empty state, the clock appears above the placeholder text.

### Acceptance (Gherkin)

```
Given the Cue Inspector pane is visible
When no cue is selected
Then a large playhead clock is rendered at the top of the inspector
And the "Select a cue" placeholder appears below it

Given a cue is selected in the inspector
Then the large playhead clock is rendered at the top of the inspector
And the cue's fields are rendered below it

Given playback is running
When the playhead advances
Then the inspector clock value updates in real time, matching the transport bar's clock
```

## Architecture

One new view, one edit. No model, command, or schema changes.

### New file: `OnlyCue/UI/InspectorClockHeader.swift`

A small, self-contained SwiftUI view.

- Observes the same playhead source the existing `TransportBar` and `PlayheadOverlay` consume (the project's playback controller / interpolator — confirmed during implementation). No new timer, no new state.
- Renders a single `Text` formatted via the existing `Time+Format.formatHMSms(_:)` helper (`OnlyCue/Utilities/Time+Format.swift:13`).
- Styling:
  - Font: `.system(size: 30, weight: .semibold, design: .monospaced)` with `.monospacedDigit()`.
  - Color: `.primary`.
  - Horizontally centered.
  - Vertical padding ~8pt top / 8pt bottom.
  - Thin `Divider()` directly beneath the readout.
- Accessibility:
  - `accessibilityIdentifier("inspectorClock")`.
  - `accessibilityLabel("Playhead time")`.
  - `accessibilityValue(<formatted string>)`.

### Edit: `OnlyCue/UI/CueInspectorView.swift`

Restructure the top-level `VStack` so that `InspectorClockHeader` is rendered *above* the existing `Group { if let cue ... else emptyState }` block. The clock sits outside the cue/empty branch so it is shown unconditionally.

The existing `.padding(12)`, `.accessibilityIdentifier("cueInspector")`, and field layout remain unchanged.

## Data flow

`PlaybackController.playheadSeconds` (existing `@Published`, name to be confirmed against the actual transport source) → `InspectorClockHeader` reads via `@ObservedObject` / `@EnvironmentObject` (whichever the rest of the UI uses) → `Time+Format.formatHMSms(_:)` → rendered `Text`.

No new state. No new commands. No persistence.

## Testing

- **Unit:** Rely on existing `Time+Format` formatter tests — no new formatter coverage needed. Add a minimal SwiftUI snapshot-style logic test only if a trivial view-level assertion can be expressed without a snapshot framework (otherwise skip).
- **UI test (`OnlyCueUITests`):** Assert the `inspectorClock` accessibility identifier exists in both states (cue selected and empty). Do **not** assert ticking values (flaky).

## Risks / open questions

- **Vertical space cost in the inspector.** ~50pt of header height is consumed on every cue. Acceptable trade-off; revisit if user feedback indicates the field area feels cramped.
- **Exact playhead source name.** The transport's `@Published` property name must be confirmed during implementation by reading `TransportBar.swift` and `PlayheadOverlay.swift`. This is a verification step, not a design risk.

## Out of scope (future work)

- SMPTE display when LTC is active.
- Click-to-seek to selected cue.
- Editable input (type a time to seek).
- Per-project format preference (decimal precision, drop-frame, etc.).
