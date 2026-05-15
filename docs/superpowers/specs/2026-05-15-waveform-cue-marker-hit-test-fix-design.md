# Waveform cue-marker hit-test fix — design

Date: 2026-05-15
Status: Approved (brainstorm)
Spec section: `docs/main-view.md` — Cue markers / direct manipulation; cross-refs `docs/superpowers/specs/2026-05-14-marker-drag-and-group-drag-design.md` and `docs/superpowers/specs/2026-05-14-main-pane-timeline-interaction-design.md`

## Summary

Cue markers in the main-pane waveform are currently unreachable by the pointer: clicks, hovers, and drags all land on the click-to-seek surface that sits above them in the Z-stack, so the pointer always seeks/scrubs the playhead instead of selecting or retiming a cue. Fix by splitting `WaveformPlayheadLayer` into two layers — a hit-testing **seek surface** that lives *below* the markers overlay, and a hit-test-disabled **playhead visual** that stays *above* it. No new gestures, commands, or schema changes.

## Motivation / observed behaviour

The marker drag/group-drag work shipped in the 2026-05-14 design is functionally complete (`CueMarkersOverlay.swift` owns the drag state, snap, retime/nudge commits) and covered by tests, but the user cannot exercise any of it from the main pane:

- Clicking a marker's cap → the playhead seeks to that x-position; the cue is not selected.
- Hovering a marker's cap → cursor stays as the seek-surface `openHand`; the marker's `resizeLeftRight` cursor and hover halo never appear.
- Dragging a marker → the timeline scrubs from the press point; the cue does not retime.

## Root cause

In `OnlyCue/UI/WaveformContainer.swift` (`waveformBody`, ~lines 96–116) the scroll content `ZStack` is, top-down:

1. `WaveformView`
2. `tempoGridOverlay()`
3. `markersOverlay()` (drag-bearing)
4. **`WaveformPlayheadLayer`** ← rendered above markers
5. `anchorRail` (hit-testing disabled)

`WaveformPlayheadLayer` (`OnlyCue/UI/WaveformPlayheadLayer.swift`, ~lines 22–37) lays down a full-bleed transparent rectangle as the seek/scrub surface:

```swift
Color.clear
    .contentShape(Rectangle())
    .gesture(timelineDragGesture(width: width))   // DragGesture(minimumDistance: 0)
    .onContinuousHover { … }                      // sets openHand cursor
```

That rectangle is opaque to hit-tests and sits above the markers, so SwiftUI's top-down hit-test resolves every press to the seek surface and never to a `CueMarkerView`. `PlayheadOverlay` itself is not the problem — it already has `.allowsHitTesting(false)`. The culprit is the *seek surface* layer wrapping it.

Gesture-priority modifiers (`.highPriorityGesture` etc.) on the markers cannot fix this: hit-testing happens before gesture arbitration; if an opaque sibling is on top, the marker view never receives the down event in the first place.

## Fix — split the playhead layer

Separate concerns so visual order and hit-test order can differ:

- **`WaveformSeekSurface`** — bears the click-to-seek + hold-to-scrub `DragGesture`, the `onContinuousHover` cursor, and the `waveformSeekSurface` accessibility identifier. Hit-testing on. Renders nothing visible.
- **`WaveformPlayheadVisual`** — owns the `TimelineView(.animation)` rendered-time loop, the `PlayheadOverlay` (line + time label), and the auto-follow `onChange`. Hit-testing off. Renders only.

Place them on either side of `markersOverlay()` in `WaveformContainer.waveformBody`. Final ZStack order, top-down:

1. `WaveformView`
2. `tempoGridOverlay()`
3. **`WaveformSeekSurface`** *(new — moved below markers)*
4. `markersOverlay()`
5. **`WaveformPlayheadVisual`** *(new — visual remains above markers so the playhead line is never occluded by a selected cap)*
6. `anchorRail`

The existing `WaveformPlayheadLayer` is removed; its responsibilities split between the two new views. `ScrubController` and `seekTask` bindings move to `WaveformSeekSurface`; the auto-follow callback (`applyAutoFollow`) and engine/duration props are needed by both halves and are wired from `WaveformContainer` as before.

### Why not the alternatives

- **Punch holes in the seek surface around each marker** — brittle (marker positions move with zoom, drag previews, snap) and breaks the "click anywhere on the timeline to seek" contract immediately adjacent to a cue.
- **Move the entire `WaveformPlayheadLayer` below markers** — visually hides the playhead line and time-label badge behind selected markers (wider cap, label badge from the 2026-05-14 inspector clock work). Regresses timeline readability.
- **Gesture priority on markers** — does not apply; hit-test ordering precedes gesture arbitration.

## Behaviour after the fix

Behaviour is the union of what the previous specs already promised; this fix is what makes them actually reachable from the main pane.

- Click on empty timeline → seek (unchanged).
- Press-and-drag on empty timeline → scrub (pause-on-press if playing, resume on release) (unchanged).
- Click on marker cap → `onSelectCue(id)` + seek to cue time (per `CueMarkersOverlay.handleTap`).
- ⌘/⇧-click on marker cap → `onToggleCue(id)` (per `CueMarkersOverlay.handleTap`).
- Drag on marker cap past 4 px → retime (solo) or nudge (group), with optional Shift-snap (per the 2026-05-14 marker-drag spec).
- Hover on marker cap → cursor becomes `resizeLeftRight`, hover halo shows.
- Hover on empty timeline → cursor becomes `openHand`.

Playhead line + time label remain visually on top, including when a selected (wider) cap sits at the same x-position.

## Risk: press-on-marker must not also begin a scrub

After the split, the seek surface and the marker view are siblings in the same `ZStack` and both carry `DragGesture(minimumDistance: 0)`. SwiftUI hit-testing should deliver the press to the topmost view at that point (the marker, after the reorder), and only that view's gesture should run — but this is the highest-risk regression of the change and must be verified explicitly:

- **Acceptance test (UI):** with a cue at t=10s, press on the marker cap and drag horizontally by 60 px. Expect the cue's stored time to change (retime) and the playhead time *not* to seek to the press x.
- If SwiftUI does start both gestures, mitigate by raising the seek surface's `DragGesture(minimumDistance:)` to a small non-zero value (e.g. 1) so the marker's zero-minimum gesture wins the arbitration on press; click-to-seek still works because the gesture's `onEnded` collapses zero-translation drags to a single seek (per `TimelineScrubOrchestrator.begin`/`.end`).

## Tests

Test-first; commit failing tests separately where practical.

### UI tests (`OnlyCueUITests/`)

Use `UITestSeedHandler` to seed a deterministic project with one media item and two cues at known times. Each scenario asserts on identifiers that already exist (`cueMarker-<id>`, `playheadOverlay`, `waveformSeekSurface`).

1. **Click on marker selects + seeks the cue, not the click x.**
   Given a cue at t=10s rendered at marker x≈M and the playhead initially at 0, when the user clicks the marker cap, then the cue becomes selected (queryable via existing selection identifiers) and the playhead time displayed in the inspector clock equals 10.000 (not the time corresponding to x=M, which would be measurably different at zoom=1 due to the cap's width).
2. **Drag on marker retimes the cue, doesn't scrub the playhead.**
   Press on marker for cue at t=10s, drag right by a known pixel delta, release. Assert the cue's time changed by the expected Δt (using `CueMarkersGeometry.time`'s inverse) AND the playhead time has not moved to the press x.
3. **Click on empty timeline still seeks.**
   Press at an x that is not within any marker's hit capsule. Assert the playhead seeks to the corresponding time.
4. **Hover on marker shows resize cursor / hover halo.** Best-effort — if `NSCursor` state is hard to assert from XCUITest, fall back to asserting the marker's hover-driven view state via an accessibility trait or the existing halo opacity wired to a testable hook. Skip with `XCTSkipIf` on hosts where pointer hover is unreliable (precedent: `2026-05-15-beat-tempo-countdown-design`).

### Unit tests (`OnlyCueTests/`)

Pure-view-model logic for this change is minimal (most behaviour is gesture wiring), but two pieces are worth pinning:

5. **`WaveformSeekSurface` and `WaveformPlayheadVisual` are independently constructible** with the same inputs the old `WaveformPlayheadLayer` accepted. Compile-level assertion that the split didn't break the public surface used by `WaveformContainer`.
6. **`waveformBody`'s ZStack order is asserted via a snapshot of the view hierarchy debug description** OR by an `accessibilityIdentifier`-ordered query — pick whichever is already established in the codebase. (Goal: future refactors that re-reorder these layers are caught by CI, not by user-reported regressions.)

## Out of scope

- Any changes to `CueCommands`, `Cue`, `ProjectModel`, or `schemaVersion`.
- Any change to playhead visuals, scrub physics, snap behaviour, or auto-follow logic — purely a layering and hit-test fix.
- Inspector-pane interactions; this spec only touches the main-pane waveform overlays.
