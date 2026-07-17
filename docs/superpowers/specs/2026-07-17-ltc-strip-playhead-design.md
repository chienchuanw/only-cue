# LTC strip moving playhead — design

**Date:** 2026-07-17
**Issue:** #653
**Status:** Approved (grilling)

Part 2 of 3 in the LTC-output improvements (② gain → ① strip → ③ multi-channel).

## Goal

Make the LTC strip functional: add a **moving playhead line** that tracks
playback, so the strip is a live timecode reference instead of a static ruler
("looks like a ruler with no function").

## Decisions (locked with the user)

- **Moving playhead line** on the LTC strip, advancing with `engine.currentTime`,
  shown at all times (paused too), like the waveform's playhead.
- **Reuse the waveform's machinery** — same smooth interpolation
  (`PlayheadInterpolator`) driven by `TimelineView(.animation)`, and the same pure
  time→x mapping (`CueMarkersGeometry.position(forTime:width:duration:)`).
- **Alignment reality (documented).** The LTC strip and the waveform are **not
  the same width / layout context** (the waveform is inset 16pt inside
  `PreviewPane`; the strip runs edge-to-edge). The LTC playhead therefore maps
  time→x across the **LTC ruler's own width** — it tracks time correctly on the
  LTC scale and is proportionally consistent with the waveform playhead, but it
  is **not pixel-aligned** to it. Pixel alignment would require making the strip
  and waveform share a width/inset — out of scope here.
- **Non-interactive.** The ruler keeps `.allowsHitTesting(false)` so clicks pass
  through to the waveform's click-to-seek above; the playhead is display-only.

## Architecture

Pure mapping + interpolation already exist and are unit-tested; this is UI
wiring.

### `LTCStrip.swift`

- Add `let engine: PlayerEngine?` (optional so previews/tests without an engine
  still render the ruler).
- Overlay the ruler `Canvas` with a `TimelineView(.animation)` that each frame:
  - computes `renderedTime` via `PlayheadInterpolator.renderedTime(observedTime:
    engine.currentTime, observedAt: engine.currentTimeObservedAt, now:
    CACurrentMediaTime(), rate: Double(engine.rate), duration: duration,
    outputLatency: engine.outputLatency)`,
  - maps it to `x = CueMarkersGeometry.position(forTime: renderedTime, width:
    rulerWidth, duration: duration)`,
  - draws a 1pt `Rectangle` (`Color.primary`, 0.85 opacity) at that x, matching
    the waveform playhead's style, spanning the ruler height.
- The overlay sits in the same coordinate space as the ruler `Canvas` (after the
  `rulerLeadingInset` padding), so the playhead lines up with the ruler's ticks.
- `.allowsHitTesting(false)` stays; add `accessibilityIdentifier("ltcStripPlayhead")`.
- When `engine == nil` (no playback context), draw no playhead.

### `DocumentView.swift`

- `ltcStripIfEnabled(_:)` passes `engine: engine` (already in scope) into `LTCStrip`.

## Testing

- **Pure mapping / interpolation:** already covered by `CueMarkersGeometry` and
  `PlayheadInterpolator` unit tests — reused, not duplicated.
- **UI (XCUITest):** seed media + enable LTC → the LTC strip renders and exposes
  a `ltcStripPlayhead` element while playing; screenshot attached. (Movement over
  time is run-verified; the pure time→x mapping is unit-tested elsewhere.)
- **Not unit-tested:** the `TimelineView`/Canvas drawing — run-verified.

## Hard-rules check

No `ProjectModel` schema change. No App Sandbox. No embedded media. macOS 14.0
floor untouched. UI-only.

## Out of scope

Pixel-aligning the LTC strip to the waveform width (a layout change). ③
Multi-channel role assignment.
</content>
