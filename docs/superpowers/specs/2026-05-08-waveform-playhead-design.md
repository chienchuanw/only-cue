# Waveform playhead indicator — design

**Date:** 2026-05-08
**Status:** Approved
**Spec sections:** `docs/architecture.md` (preview pane), `docs/verification.md` (new step)

## Problem

The audio waveform shows the entire track and cue markers, but during playback there's no visual indication of where the play position currently is. Users have to read the transport bar's HH:MM:SS field to locate themselves in the waveform.

## Goal

Render a playhead indicator on the audio waveform that:

1. Tracks `PlayerEngine.currentTime` as a vertical line.
2. Displays a floating HH:MM:SS label near the playhead.
3. Supports drag-to-scrub: pause on drag start, seek on release, resume playback if it was playing.

Out of scope: video-strip playhead, live audio scrubbing, snap-to-cue, keyboard nudge.

## Design

### Components

**`PlayheadOverlay`** (new, `OnlyCue/UI/PlayheadOverlay.swift`)

Pure rendering view. Inputs:

- `currentTime: TimeInterval`
- `duration: TimeInterval`
- `width: CGFloat` (from `GeometryReader` in the parent)

Renders:

- 1–2pt vertical line at `CueMarkersGeometry.position(forTime: currentTime, width: width, duration: duration)`.
- A small HH:MM:SS label above the line, formatted with the existing `Time+Format` helper. The label's x position is clamped to `[0, width - labelWidth]` so it never clips at the edges.

The overlay does not own any state and has no engine dependency — it's a deterministic view of its inputs.

**`WaveformContainer`** (modified)

Add two parameters:

- `showsPlayhead: Bool = false` — opt-in flag. Default false preserves today's behavior.
- `engine: PlayerEngine? = nil` — required when `showsPlayhead` is true; ignored otherwise.

When `showsPlayhead` is true and `engine != nil`, the container:

- Layers `PlayheadOverlay` over `WaveformView`, driven by `engine.currentTime` (or `scrubState.scrubTime` while dragging — see below).
- Attaches a drag gesture to a 12pt-wide invisible grabber centered on the playhead line. The grabber's narrow hit zone is what avoids stealing drags from cue markers and from the existing tap-to-seek surface.

When `showsPlayhead` is false (the video-strip waveform), behavior is byte-identical to today.

**`PreviewPane`** (modified)

In `audioContent`, pass `showsPlayhead: true, engine: engine` to `WaveformContainer`. `videoContent` continues to pass the defaults, so the 100pt video strip stays a plain waveform.

### Scrub interaction

State held in `WaveformContainer`:

```swift
struct ScrubState {
    let resumeOnRelease: Bool
    var scrubTime: TimeInterval
}
@State private var scrubState: ScrubState?
```

Drag gesture lifecycle:

- **onChanged, first call:**
  - Capture `resumeOnRelease = engine.rate > 0`.
  - Call `engine.pause()`.
  - Compute `scrubTime` from the playhead's original time plus cumulative `value.translation.width` via `CueMarkersGeometry.time(originalTime:dx:width:duration:)` (already clamps to `[0, duration]`).
  - Set `scrubState`.
- **onChanged, subsequent:** update `scrubState.scrubTime` only. No live `seek()` calls during drag — quieter audio, no seek backpressure.
- **onEnded:**
  - `await engine.seek(to: scrubTime)`.
  - If `resumeOnRelease`, call `engine.play()`.
  - Clear `scrubState`.

While `scrubState != nil`, the overlay renders at `scrubState.scrubTime` instead of `engine.currentTime` — this avoids the perceived lag/flicker of waiting for the next periodic time observer tick after a seek.

No timers or manual throttling: SwiftUI state coalesces re-renders, and the periodic time observer already fires at 10 Hz during normal playback.

### Geometry reuse

`CueMarkersGeometry.position(forTime:width:duration:)` and `.time(originalTime:dx:width:duration:)` already exist for cue markers. The playhead reuses both. No new geometry helpers.

### Hit-zone reasoning

A full-width drag handler on the overlay would conflict with:

- Tap-to-seek on empty waveform area.
- Cue marker drag (markers sit on top of the waveform at specific x positions).

A 12pt-wide grabber centered on the playhead line is a small, focused hit target. Markers and empty-area taps continue to work because they're spatially separated from the playhead's grabber most of the time. When a cue marker happens to sit directly under the playhead, marker drag wins because the layering order is: `WaveformView` (base) → `PlayheadOverlay` → `CueMarkersOverlay` (top).

## Testing

TDD red→green. Tests live in `OnlyCueTests/`.

**Pure geometry / rendering**

- `playhead_position_atHalfDuration_isHalfWidth`
- `playhead_label_formatsHHMMSS`
- `playhead_label_clampsAtLeftEdge`
- `playhead_label_clampsAtRightEdge`

**Scrub controller**

Extract drag logic into a `ScrubController` struct so it's unit-testable without SwiftUI:

- `dragBegan_whilePlaying_marksResumeTrue`
- `dragBegan_whilePaused_marksResumeFalse`
- `scrubTime_clampsToDuration`
- `scrubTime_clampsToZero`

**UI test:** deferred. Drag-on-grabber is hard to fake reliably in XCUITest given the small hit zone; the controller unit tests cover the meaningful logic.

## Files

- New: `OnlyCue/UI/PlayheadOverlay.swift`
- New: `OnlyCue/UI/ScrubController.swift` (extracted scrub logic)
- New: `OnlyCueTests/PlayheadOverlayTests.swift`
- New: `OnlyCueTests/ScrubControllerTests.swift`
- Modified: `OnlyCue/UI/WaveformContainer.swift`
- Modified: `OnlyCue/UI/PreviewPane.swift`
- Modified: `docs/verification.md` (add a step for the playhead)

## Acceptance criteria (Gherkin)

```
Given an audio file is loaded and playing
When the user observes the audio waveform
Then a vertical playhead line is visible at the current playback position
And an HH:MM:SS label is shown near the line

Given an audio file is playing
When the user drags the playhead to a new position
Then playback pauses during the drag
And the playhead line tracks the cursor
And on release, playback seeks to the dragged position
And playback resumes from there

Given an audio file is paused
When the user drags the playhead to a new position
Then on release, playback seeks to the dragged position
And playback remains paused
```
