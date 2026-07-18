# Fix: severe playhead judder at max zoom during follow playback (#681)

Status: approved
Issue: #681
Parent: #677 (`2026-07-18-follow-scroll-shimmer-and-pause-jump-fix.md`)

## Problem

At 64× horizontal zoom, during playback with Auto-Scroll on, the preview-area
playhead juddres severely. Reproduces with LTC on or off (LTC only adds load).
Smooth at ~3×, so it is a zoom-amplified regression from the #677 follow work.

## Root cause — two factors, both amplified by zoom

- **A — two independent time samples.** #677 computes the follow `scrollOffset`
  per frame in `WaveformContainer.offsetScrollContent`'s `TimelineView`, while
  the playhead line is drawn by `WaveformPlayheadVisual`'s **separate**
  `TimelineView`; each samples `renderedTime()` at its own instant. The
  per-frame jitter between the two closures is multiplied by
  `pxPerSecond ∝ contentWidth = viewport × zoom`, so at 64× it is visible
  judder. The LTC strip has the same split (ruler-offset vs playhead).
- **B — per-frame giant Canvas.** `WaveformView` redraws the full `contentWidth`
  (≈ viewport × 64 ≈ 70 000 px) envelope every frame and upsamples the ~12 000
  source peaks into ~70 000 columns → a ~140 000-point path per frame → dropped
  frames.

## Fix

- **Unify the time source.** Compute `renderedTime()` **once** per frame in the
  offset `TimelineView` and feed it to both the offset and the playhead: thread
  `overrideTime` into `WaveformPlayheadVisual`, which — while following — draws a
  static `PlayheadOverlay(currentTime: overrideTime)` instead of running its own
  `TimelineView`. Same unification in `LTCStrip` (the ruler offset and the LTC
  playhead share one `renderedTime()`). The on-screen playhead is then
  analytically `viewport × followFraction` every frame — no cross-`TimelineView`
  desync, so no zoom-amplified jitter.
- **Cap the column count.** `WaveformView` buckets into
  `min(Int(contentWidth), peaks.count)` columns instead of `Int(contentWidth)`.
  Lossless — above the source resolution the extra columns are collinear
  interpolations of the same peaks — and ~6× cheaper per frame at 64×.

## What stays the same

- The #677 fixed-playhead + flowing-waveform model, shimmer fix (pixel-snap) and
  pause-jump fix. Low zoom / manual scroll / 1× unchanged.
- `ProjectModel` schema, App Sandbox (none, ADR-007), macOS 14.0 floor,
  version number (release decided separately).

## Test plan (TDD)

- **Unit** (`WaveformViewTests` or similar): `WaveformView.bucketCount(width:
  peakCount:)` returns `min(Int(width.rounded()), peakCount)` and never exceeds
  the source resolution; ≥ 1 for a non-empty waveform.
- **Unit invariant** (existing `WaveformZoomControllerTests`): in the follow
  region `playheadContentX(t) − snappedFollowScrollOffset(t) ≈ viewport × 1/3`.
- **UITest** (`WaveformFollowUITests`): a deep-zoom (≫ 3×) follow-playback smoke
  that the playhead still holds near 1/3 (the judder itself is perceptual —
  pinned here by position, the mechanism by the unit tests).
