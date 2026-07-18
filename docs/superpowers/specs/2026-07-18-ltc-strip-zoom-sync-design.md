# LTC strip zoom-sync with the waveform — design

**Date:** 2026-07-18
**Issue:** #669
**Status:** Approved (grilling)

## Goal

When the waveform is horizontally zoomed (zoom > 1) and scrolled, the LTC strip
must mirror the same zoom + scroll so the LTC playhead stays on the same
vertical line as the waveform playhead. Today the strip renders at the unzoomed
width, so the playheads diverge once zoomed (explicitly out of scope in #663).

## Decisions (locked with the user)

- **Full sync:** the LTC ruler's ticks scale with zoom and it shows the exact
  same time window as the waveform viewport (mirrors `scrollOffset`). Passive —
  no its own scroll gesture/scrollbar.

## Architecture

All zoom state already lives on one `@Observable WaveformZoomController`
(`zoom`, `scrollOffset`, `viewportWidth`). Share that single instance between
the waveform and the LTC strip.

- **`DocumentView`**: own the controller — `@State private var waveformZoom =
  WaveformZoomController()`. Pass it to `PreviewPane` (→ `WaveformContainer`) and
  to the LTC strip (`ltcStripIfEnabled`).
- **`PreviewPane`**: new `waveformZoom` param, threaded into `WaveformContainer`.
- **`WaveformContainer`**: change `@State var zoom = WaveformZoomController()` to
  an injected `var zoom: WaveformZoomController`. Its load path still calls
  `zoom.reset(...)` on each new asset, so switching clips still resets zoom.
- **`LTCStrip`**: new optional `zoom: WaveformZoomController?` (nil in
  previews/tests ⇒ today's 1× behaviour). Render the ruler content across the
  **zoomed content width** and shift it by the shared scroll offset:
  - `contentWidth = WaveformZoomController.contentWidth(viewportWidth:)` (a new
    pure helper `max(viewportWidth * zoom, viewportWidth)`, shared with
    `WaveformContainer` so the two never diverge).
  - Draw ticks + playhead across `contentWidth`, then `.offset(x: -scrollOffset)`
    inside a viewport-width clipped frame — the same window the waveform's
    `ScrollView` shows. Both playheads map via `CueMarkersGeometry.position(_,
    width: contentWidth, _)` then subtract `scrollOffset`, so they coincide.
  - The LTC strip's own width equals the waveform viewport (both inset by
    `PreviewLayout.playheadTrackInset`, #663), so `contentWidth` and
    `scrollOffset` mean the same pixels in both.

### Compatibility

No `ProjectModel` / schema change. At zoom == 1 (`contentWidth == viewportWidth`,
`scrollOffset == 0`) the strip renders exactly as today. Waveform zoom/scroll/
auto-follow logic is unchanged — only the controller's *owner* moves.

## Testing

- **Unit:** `WaveformZoomController.contentWidth(viewportWidth:)` (the shared
  helper) — `max(vw*zoom, vw)`, never below `vw`. Existing zoom-controller tests
  stand (logic unchanged).
- **UI (XCUITest):** with LTC enabled, zoom in a few times (View ▸ Zoom In
  Horizontally), seek to a visible cue, and assert the LTC playhead's x matches
  the waveform playhead's x (red→green: they diverge before sync, coincide
  after). A zoom==1 alignment case already exists (`LTCStripAlignmentUITests`).

## Hard-rules check

No schema change, no App Sandbox, no embedded media, macOS 14.0 floor untouched.

## Out of scope

Vertical zoom; giving the LTC strip its own scroll gesture (it stays passive).
