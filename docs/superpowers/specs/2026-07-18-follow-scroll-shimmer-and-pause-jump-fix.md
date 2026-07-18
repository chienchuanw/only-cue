# Fix: follow-scroll shimmer + pause playhead jump (#677, follow-up to #675)

Status: approved
Issue: #677
Parent: #675 (`2026-07-18-smooth-playhead-follow-scrolling-design.md`)

## Problem

After #675 shipped continuous playhead-follow scrolling (fixed playhead at ~1/3,
waveform flows underneath), two rough edges remain during **zoomed** playback:

- **A — waveform shimmer.** The playhead line holds steady but the waveform
  envelope shimmers / water-ripples as it flows.
- **B — playhead jumps forward one notch on pause.** Pausing during zoomed
  playback snaps the playhead forward. Imperceptible at 1×.

## Root cause

Both come from how the follow offset relates to the playhead.

- The follow `scrollOffset` is written in `WaveformPlayheadVisual`'s
  `.onChange(of: context.date)` (into the `@Observable` controller), while the
  playhead line is drawn in the same `TimelineView` body from its own
  `renderedTime()`. These are **two `renderedTime()` samples, one frame apart**.
  During playback the fixed playhead hides the mismatch; on pause the follow
  stops (guarded on `engine.isPlaying`) and the playhead settles to the true
  time, so the accumulated time delta shows as a jump. The on-screen size of the
  jump is `Δtime × pxPerSecond`, and `pxPerSecond ∝ contentWidth = viewport ×
  zoom` — so it is only visible when zoomed (B).
- The render offset changes by **sub-pixel** amounts each frame. Translating the
  dense, high-contrast waveform envelope by fractional pixels makes Core
  Animation resample it (bilinear), which reads as shimmer (A).

`WaveformView` draws the whole `contentWidth` envelope into one `Canvas` and the
parent `.offset(x:)` translates it — so this is layer-translation shimmer, not
per-frame re-rasterization.

## Fix

1. **`WaveformZoomController.snappedFollowScrollOffset(playheadContentX:
   viewportWidth:contentWidth:displayScale:)`** — a pure function returning
   `followScrollOffset(...)` aligned to whole device pixels
   (`round(offset * displayScale) / displayScale`), still clamped to
   `[0, contentWidth − viewport]`. `displayScale ≤ 0` falls back to the
   unsnapped clamped value.
2. **Per-frame, single-source offset while following.** The waveform *and* the
   LTC strip compute the follow offset each frame from `renderedTime()` inside
   their own `TimelineView(.animation)` (no `@State` write, so no #676 render
   loop). Non-following (manual scroll / zoom / 1×) still uses the stored
   `scrollOffset`. Because the offset and the playhead now come from the *same*
   `renderedTime()` in the *same* frame, the playhead sits analytically at
   `viewport × followFraction` throughout the follow region → no pause jump (B).
3. **Persist once on pause.** On `engine.isPlaying → false`, write the last
   follow offset into the stored `scrollOffset` a single time, so play→pause is
   seamless and later manual scrolling starts from the correct position.

The pixel-snapped render offset makes the envelope translate in whole device
pixels → no sub-pixel resampling → no shimmer (A).

## What stays the same

- The fixed-playhead + flowing-waveform model from #675.
- `ProjectModel` schema (no change), App Sandbox (none, ADR-007), macOS 14.0
  floor (ADR-001), version number (release decided separately).
- 1× playback and manual scroll-wheel / pinch behavior — unchanged (no
  regression).

## Test plan (TDD)

- **Unit** (`WaveformZoomControllerTests`):
  - `snappedFollowScrollOffset` result is device-pixel aligned and clamped to
    `[0, contentWidth − viewport]`; `displayScale ≤ 0` → unsnapped clamped value.
  - **Invariant:** across the follow region, `playheadContentX(t) −
    snappedFollowScrollOffset(t) ≈ viewport × followFraction` within ≤ 1 device
    pixel (this is the property that makes the pause jump impossible).
- **UITest** (`WaveformFollowUITests`): zoom, play, pause; assert the playhead
  is still ~1/3 of the viewport after pausing (no forward jump).
