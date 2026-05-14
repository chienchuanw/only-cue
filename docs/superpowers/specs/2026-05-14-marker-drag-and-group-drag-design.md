# Marker drag & group drag — design

Date: 2026-05-14
Status: Approved (brainstorm)
Spec section: `docs/main-view.md` — Cue markers / direct manipulation

## Summary

Make cue markers on the main-pane waveform directly draggable to retime cues, and let a multi-selection move together rigidly when any selected marker is dragged. Shift quantises the drag to the tempo grid when one exists. No schema change; reuses existing `CueCommands.retime` and `CueCommands.nudgeCues`.

## Motivation

Today, retiming a cue from the main pane requires either keyboard nudging (`Option+←/→`) or snap-to-playhead (`S`). The single-marker `DragGesture` already exists in `CueMarkersOverlay.swift` and commits via `CueCommands.retime`, but:

- It has no hover affordance, so users don't know markers are draggable.
- It has no group behavior — dragging one of N selected markers only moves that one, even though `nudgeCues(_:by:)` already supports rigid group shifts.
- It does not interact with the tempo grid, even though the grid is shown beneath the markers.

This spec closes those gaps with no new commands, no schema bump, and no new data flow.

## Interaction model

### Single-marker drag (already exists; touched for consistency)

- Drag a marker → that cue retimes. Live visual offset follows the cursor; commit on mouse-up via `CueCommands.retime(cueId:to:)`.
- Below the 4-px threshold the gesture is a click (select + seek), as today.
- **New:** holding **Shift** during the drag snaps the dragged cue's resulting time to the nearest beat of the active `DerivedTempoGrid`. No grid → Shift is a no-op.

### Group drag (new)

- **Trigger:** mouse-down on a marker that is in `selectedCueIDs`, and `|selectedCueIDs| ≥ 2`.
- **Behavior:** rigid Δ shift. Every selected marker's visual position tracks the cursor live by the same pixel Δ. Each cue clamps individually at `t = 0` (group may compress against the left edge).
- **Shift-snap:** when Shift is held, the snap is anchored on the **grabbed cue** — its resulting time quantises to the nearest beat, and the rest of the group rides along by that same pixel Δ. (Per-cue independent snapping would warp the group; anchoring on one cue preserves spacing.)
- **Commit:** one call to `CueCommands.nudgeCues(selection, by: Δt, ...)`. Single undo entry titled "Nudge Cues" (existing).

### Drag-on-unselected while multi-selection is active

- On mouse-down on a marker that is **not** in `selectedCueIDs`: replace the selection with just that cue (`onSelectCue(grabbedID)`), then drag it solo as a normal single drag. Mirrors plain-click behavior.

### Cursor affordance

- While hovering a marker's hit-capsule, pointer becomes `NSCursor.resizeLeftRight`. Makes the drag affordance discoverable.

## Architecture

### State lifting in `CueMarkersOverlay`

Today each `CueMarkerView` owns `@State dragOffset`. That's fine for solo drag but cannot drive a synchronised group animation. Drag state moves up to the overlay:

```swift
@State private var activeDrag: ActiveDrag? = nil

private struct ActiveDrag {
    let grabbedID: Cue.ID
    let isGroup: Bool          // grabbedID ∈ selectedCueIDs ∧ |sel| ≥ 2
    let movingIDs: Set<Cue.ID> // {grabbedID} for solo, selectedCueIDs for group
    var dxRaw: CGFloat         // raw translation.width from DragGesture
    var dxApplied: CGFloat     // after optional Shift-snap; drives render + commit
}
```

`CueMarkerView` becomes a pure renderer. It receives:

- `visualOffset: CGFloat` — `0` unless its cue id is in `activeDrag.movingIDs`, otherwise `activeDrag.dxApplied`.
- Closures: `onDragChanged(id, translationWidth)`, `onDragEnded(id, translationWidth)`, plus the existing select/seek closures.

It owns no drag-related `@State`.

### Gesture lifecycle (overlay-level)

- **First `onChanged`:**
  - Compute `isGroup = selectedCueIDs.contains(grabbedID) && selectedCueIDs.count >= 2`.
  - If `!selectedCueIDs.contains(grabbedID) && selectedCueIDs.count >= 2`: call `onSelectCue(grabbedID)` first (replaces selection), then start a solo drag.
  - Initialise `activeDrag`.
- **Subsequent `onChanged`:**
  - Update `dxRaw = translation.width`.
  - If `NSEvent.modifierFlags.contains(.shift)` and `tempoGrid != nil`: `dxApplied = CueMarkersGeometry.snapDeltaToBeat(dxPixels: dxRaw, anchorTime: grabbedCue.time, grid: tempoGrid, width: geometry.width, duration: duration)`. Else `dxApplied = dxRaw`.
- **`onEnded`:**
  - If `|dxApplied| < dragThreshold` (4 px) → treat as tap (existing select/seek path).
  - Else: `Δt = CueMarkersGeometry.time(originalTime: grabbedCue.time, dx: dxApplied, ...) - grabbedCue.time`.
    - Solo → `onRetime(grabbedID, grabbedCue.time + Δt)`.
    - Group → `onNudge(activeDrag.movingIDs, Δt)`.
  - Clear `activeDrag`.

### Snap helper

In `CueMarkersGeometry.swift`:

```swift
static func snapDeltaToBeat(
    dxPixels: CGFloat,
    anchorTime: TimeInterval,
    grid: DerivedTempoGrid,
    width: CGFloat,
    duration: TimeInterval
) -> CGFloat
```

Computes the target time of the anchor under `dxPixels`, snaps that time to the nearest grid beat, and returns the pixel Δ that yields the snapped anchor time. Pure, easy to unit-test.

### Wiring

`CueMarkersOverlay` already receives `selectedCueIDs`, `onSelectCue`, `onToggleCue`, `onRetime`. The call-site (currently in the document binding layer; see `OnlyCue/UI/DocumentView+Bindings.swift` or the overlay's parent) adds:

```swift
onNudge: { ids, delta in
    CueCommands.nudgeCues(ids, by: delta, document: document, undoManager: undoManager)
},
tempoGrid: derivedTempoGrid     // optional; nil disables Shift-snap
```

### Cursor

Thin `.onContinuousHover` on the hit-capsule pushes/pops `NSCursor.resizeLeftRight`. Scoped to the existing hit area so it can't bleed into the waveform background.

## Testing

### Unit tests

- `CueMarkersGeometryTests`
  - `snapDeltaToBeat` snaps anchor time to the nearest beat for a uniform grid.
  - `snapDeltaToBeat` returns `dxPixels` unchanged when grid is degenerate (single beat / zero spacing).
  - Group Δt math: with selection `[t=0.1, t=2.0, t=5.0]` and Δt = -1.0, the result is `[0.0, 1.0, 4.0]` (individual clamp at 0).

- `CueMarkersOverlayTests` (new or extend)
  - On drag-end with `|dxApplied| ≥ threshold` and grabbed cue is solo-selected → invokes `onRetime` once, `onNudge` zero times.
  - On drag-end with grabbed cue in a multi-selection → invokes `onNudge` once with the full selection set, `onRetime` zero times.
  - On drag-start of an unselected marker while multi-selection exists → invokes `onSelectCue(grabbedID)` first, then commits via `onRetime` (solo).

### UI tests (Gherkin)

`OnlyCueUITests/CueGroupDragTests.swift` (new):

```
Scenario: Group drag shifts all selected cues rigidly
  Given a project with cues at 1s, 3s, 6s
  And all three cues are selected
  When the user drags the marker at 3s by +5s on the waveform
  Then the cues are at 6s, 8s, 11s
  And the undo stack has one entry titled "Nudge Cues"

Scenario: Dragging an unselected marker replaces the selection
  Given a project with cues at 1s, 3s, 6s
  And cues at 1s and 3s are selected
  When the user drags the marker at 6s by +2s
  Then only the cue at 6s has moved (now at 8s)
  And the selection is exactly { cue at 8s }

Scenario: Shift snaps the group to the tempo grid
  Given a project with cues at 1.00s, 3.00s
  And a 120 BPM tempo grid (beats every 0.5s)
  And both cues are selected
  When the user drags the marker at 1.00s by +0.40s with Shift held
  Then the cues are at 1.50s, 3.50s
```

## Files affected

| File | Change |
|---|---|
| `OnlyCue/UI/CueMarkersOverlay.swift` | Lift drag state, branch solo/group, Shift-snap, replace-on-grab, hover cursor |
| `OnlyCue/UI/CueMarkersGeometry.swift` | Add `snapDeltaToBeat` helper |
| `OnlyCue/UI/DocumentView+Bindings.swift` (or marker overlay parent) | Pass `onNudge` + `tempoGrid` |
| `OnlyCueTests/CueMarkersGeometryTests.swift` | Unit tests for snap + group Δ math |
| `OnlyCueTests/CueMarkersOverlayTests.swift` | Solo vs group commit dispatch, replace-on-grab |
| `OnlyCueUITests/CueGroupDragTests.swift` (new) | Group drag, replace-on-grab, Shift-snap scenarios |

No new commands. No schema change. Reuses `CueCommands.retime` and `CueCommands.nudgeCues` with existing undo semantics.

## Out of scope

- Proportional / stretch drag (scale spacing around an anchor).
- Auto-scroll when dragging past the visible waveform edge.
- Cue-to-cue magnetism (snap to nearby cues).
- Inertia, copy-on-drag (e.g. Option-drag to duplicate).
- Touch / trackpad gesture differentiation beyond what `DragGesture` already provides.
