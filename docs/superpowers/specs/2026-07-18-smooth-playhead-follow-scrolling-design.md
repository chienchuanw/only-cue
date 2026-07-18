# Smooth continuous playhead-follow scrolling — design

**Date:** 2026-07-18
**Issue:** #675
**Status:** Approved (grilling)

## Goal

During playback (zoom > 1, "Auto-Scroll Waveform" on) keep the playhead always
visible by **fixing it at ~1/3 of the viewport** and scrolling the waveform
**continuously and smoothly** underneath it — replacing today's jump-when-the-
playhead-hits-80% behaviour and the ~1-second anchor-bucket quantization.

## Decisions (locked with the user)

- **Fixed playhead, waveform flows.** The playhead sits at a constant x; the
  waveform scrolls continuously at playback speed.
- **Position: ~1/3 from the left** (look-ahead — more upcoming waveform / cues).
- **Reuse the existing "Auto-Scroll Waveform" toggle.** On → smooth 1/3 follow;
  off → no follow (manual scroll, playhead may leave the view).
- **Clamp at the ends.** Near the start the playhead sits left of 1/3 (the view
  can't scroll past 0); near the end it drifts right of 1/3 as the scroll clamps
  at max. Standard.

## Root cause of the jumpiness

`WaveformContainer` scrolls a real `ScrollView` via `.scrollPosition(id:
$leadingAnchor)` — an *anchor-bucket* hack (macOS 14 has no pixel-offset scroll
API), buckets ≈ 1s wide. And `autoFollowAdjustment` only scrolls once the
playhead crosses the 80% mark, jumping it back to 20%. Both are why it's jumpy.

## Architecture — continuous pixel-offset rendering

The zoom controller **already** maintains a continuous pixel `scrollOffset`
(the magnifier's `setZoom` and `scrollToReveal` compute it); the anchor buckets
were only a *rendering* workaround. So render directly off `scrollOffset`:

- **`WaveformContainer.waveformBody`:** replace the `ScrollView` + `scrollPosition`
  + `anchorRail` with `scrollContent(...).frame(width: contentWidth).offset(x:
  -scrollOffset).frame(width: viewport).clipped()` — the same continuous
  offset/clip the LTC strip uses (#663/#669). No buckets ⇒ smooth.
- **Manual scroll:** a small `NSViewRepresentable` scroll-wheel catcher reports
  horizontal `scrollingDeltaX` (and ⇧+deltaY) → adjust `scrollOffset`, clamped
  to `[0, contentWidth − viewport]`. (Replaces the ScrollView's trackpad scroll.)
- **Auto-follow (continuous):** `WaveformZoomController.followScrollOffset(playhead
  ContentX:viewportWidth:contentWidth:)` returns `clamp(playheadContentX −
  followFraction·viewport)` with `followFraction = 1/3`, applied **every frame**
  while `isPlaying && followsPlayhead && zoom > 1` (driven by the playhead's
  `TimelineView`). No trailing-threshold gate ⇒ continuous.
- **Remove** `leadingAnchor`, `anchorRail`, `isProgrammaticAnchor`, the anchor
  math in `applyZoomIn`/`applyAutoFollow`/`reset`/`load`, and `snappedScrollOffset`.
- **LTC alignment (#669):** `renderedScrollOffset` now equals `scrollOffset`
  (continuous — no snapping), so the LTC strip stays collinear. Kept in sync
  wherever `scrollOffset` changes.
- Everything still clamps `scrollOffset` to `[0, contentWidth − viewport]`; at
  zoom 1 (`contentWidth == viewport`) offset is 0 and manual scroll is a no-op.

## Compatibility / risk

No schema change. This is the app's most historically fragile view (NSSplitView
constraint recursion #269/#297/#271, marker hit-tests #285/#534) — but those
concern the cue-list split and marker gestures, not the waveform ScrollView
itself. The seek surface, marker drags, magnifier zoom, and cue-reveal keep
working off the same `scrollOffset` they already used. Verify: LTC zoom
alignment still holds; zoom-in/out anchoring; seek/scrub; marker retime.

## Testing

- **Unit:** `followScrollOffset(...)` — playhead at 1/3, clamped at 0 and max
  (`WaveformZoomControllerTests`). Existing zoom/scroll/magnifier tests stay
  green (the pixel `scrollOffset` math is unchanged).
- **UI (XCUITest):** the existing `LTCStripAlignmentUITests` zoomed case must
  still pass (proves the continuous offset keeps LTC ↔ waveform aligned). A
  screenshot with playback zoomed shows the playhead near 1/3. Smoothness itself
  is visual — screenshot/manual-verified.

## Hard-rules check

No schema change, no App Sandbox, no embedded media, macOS 14.0 floor untouched.

## Out of scope

Vertical scroll; native scroll momentum (basic wheel scrolling only); changing
the follow behaviour at zoom 1 (whole track already fits).
