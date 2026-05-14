# Main Pane timeline interaction design

**Date:** 2026-05-14
**Status:** Approved (brainstorm)
**Scope:** Waveform-area pointer interaction in the Main Pane — click-to-seek, hold-to-scrub, playhead-grabber removal, and cue marker hover affordance.

## Motivation

Today the Main Pane has three overlapping interaction surfaces on the waveform:

1. Tap anywhere on the waveform body → `onTapGesture` seeks to that point (`WaveformPlayheadLayer.swift:30-40`).
2. A dedicated 12-px grabber centered on the playhead line lets the user drag to scrub, with pause-on-press / resume-on-release semantics (`WaveformPlayheadLayer.swift:44-55`, `scrubGesture(width:)` at lines 88-110).
3. Cue markers are individually selectable and draggable (`CueMarkersOverlay.swift`); on hover only the cursor changes (`.resizeLeftRight`), with no visual response on the marker itself.

This split has two problems. First, the dedicated playhead grabber is a small, easy-to-miss target that duplicates what a "hold on the timeline" gesture would do more naturally. Second, cue markers lack the visual hover affordance the rest of the UI uses for selectable elements, so users don't realize markers are interactive until they click.

## Goals

- A single pointer gesture on the waveform body that handles both click-to-seek and click-and-hold-to-scrub.
- Remove the dedicated playhead grabber; the visible playhead line/label remain as pure indicators.
- Add a visible hover affordance to cue markers that reads as "selectable", without competing with the selected-state styling.

## Non-goals

- Reworking cue marker drag, snap, group-nudge, or selection logic — those stay exactly as today.
- Keyboard or touch-bar equivalents for hold-scrub.
- Animation of the playhead beyond what `ScrubController.scrubTime` already drives.
- Any change to playback rate, auto-follow, or zoom behavior.

## Behavioral spec

### Click and hold-to-scrub (replaces playhead grabber)

- Pressing anywhere on the waveform body (outside any cue marker hit zone) immediately seeks the playhead to the pressed x-position.
- If transport was playing, the press also pauses playback.
- Continuing to hold and drag moves the playhead under the cursor in real time (scrub).
- On release:
  - The transport seeks to the final position.
  - If transport was playing at press time, playback resumes from the final position.
  - If transport was paused at press time, transport remains paused.
- A pure click (zero-translation drag) is the degenerate case: it seeks once. If transport was playing, it will momentarily pause on press and resume on release — a sub-frame blip that is not user-perceptible. If transport was paused, neither `pause` nor `play` fires.

### Cue marker hover affordance

- When the cursor enters a cue marker's hit zone (14-px capsule), a soft halo appears behind the cap: accent-colored (or per-cue color if set), roughly 8 px larger than the cap, ~35 % alpha, with a small blur.
- When the cursor leaves, the halo disappears.
- The halo is suppressed while the marker is in the selected state (the thicker selected cap already conveys focus).
- Cursor change (`.resizeLeftRight`) on the same hit zone is unchanged.

### Preserved behaviors (must not regress)

- Click on a cue marker selects it and seeks to its time (`CueMarkersOverlay.handleTap`).
- ⌘- or ⇧-click on a marker toggles selection (`onToggleCue`).
- Drag on a marker retimes it (`onRetime`) or rigid-shifts a selected group (`onNudge`).
- Shift-held drag snaps to the nearest beat when the tempo grid is non-empty.
- Tap-vs-drag threshold (4 px raw translation) is unchanged.

## Implementation

### File: `OnlyCue/UI/WaveformPlayheadLayer.swift`

- Replace the `Color.clear.contentShape(Rectangle()).onTapGesture` seek surface (lines 30-40) with the same `Color.clear` carrying a `DragGesture(minimumDistance: 0)`.
- Delete the 12-px grabber block (lines 44-55) and the `scrubGesture(width:)` helper (lines 88-110). The `PlayheadOverlay` line + label remain, drawn with `.allowsHitTesting(false)`.
- The new gesture reuses the existing `ScrubController`:
  - First `onChanged` event: compute `pressedTime = CueMarkersGeometry.time(forX: value.startLocation.x, width: width, duration: duration)`; call `scrub.begin(originalTime: pressedTime, isPlaying: engine.isPlaying)`; if `engine.isPlaying`, call `engine.pause()`; set `closedHand` cursor.
  - Subsequent `onChanged`: `scrub.update(dx: value.translation.width, width: width, duration: duration)`.
  - `onEnded`: pop the scrub state via `scrub.end()`, cancel any pending `seekTask`, then `engine.seek(to: finished.scrubTime)`; if `finished.resumeOnRelease`, `engine.play()`; restore arrow cursor.
- The seek-surface `Color.clear` keeps its `accessibilityIdentifier("waveformSeekSurface")`.
- The `playheadGrabber` accessibility identifier is removed along with the grabber view; any UI test referencing it must be updated.

### File: `OnlyCue/UI/CueMarkersOverlay.swift` (`CueMarkerView` only)

- Add `@State private var isHovered: Bool = false`.
- On the existing hit-zone `Capsule` (lines 207-215), replace the cursor-only `onHover` with a combined handler:
  - `inside == true` → `isHovered = true`, `NSCursor.resizeLeftRight.push()`.
  - `inside == false` → `isHovered = false`, `NSCursor.pop()`.
- Inside the marker `ZStack(alignment: .top)`, **before** the line/cap shapes (so the halo sits underneath), add:

  ```swift
  Circle()
      .fill(markerColor)
      .frame(width: style.capWidth + 8, height: style.capWidth + 8)
      .opacity(showHalo ? 0.35 : 0)
      .blur(radius: 2)
      .animation(.easeOut(duration: 0.12), value: showHalo)
  ```

- `showHalo` is a computed `Bool`: `isHovered && !isSelected`.
- No change to the marker's `DragGesture`, drag/tap threshold, or accessibility identifiers.

### Z-order and hit priority

Cue markers must continue to take pointer hits over the new timeline drag surface. In the current `WaveformContainer.body`, `markersOverlay()` is drawn before `WaveformPlayheadLayer`, so the seek surface is technically above the markers. Markers still win today because their `DragGesture(minimumDistance: 0)` is hit-tested within the 14-px capsule before the surrounding seek surface receives the event.

If the gesture promotion in `WaveformPlayheadLayer` regresses marker priority during implementation, the fallback is either:

1. Attach the timeline drag as `.simultaneousGesture` on the seek surface (markers win normal gesture arbitration), or
2. Move `markersOverlay()` to be rendered **after** `WaveformPlayheadLayer` in the ZStack.

Decision between (1) and (2) is deferred to implementation; both are local edits with no behavioral side effects beyond hit ordering.

## Testing

### Unit

- `ScrubController` existing tests stay green — `begin/update/end` semantics unchanged.
- Extend or add a pure-function test for the gesture mapping in `WaveformPlayheadLayer`:
  - A drag ending with `translation.width == 0` at location `x` issues `seek(timeAt(x))`; when transport was paused at press, neither `engine.pause` nor `engine.play` is called. When transport was playing at press, `pause` fires once on the first `onChanged` and `play` fires once on `onEnded` (the imperceptible click-blip).
  - A drag with non-zero translation when `isPlaying == true` at press calls `engine.pause()` exactly once on the first `onChanged` and `engine.play()` exactly once on `onEnded`.
  - A drag with non-zero translation when `isPlaying == false` at press calls neither `pause` nor `play`, and ends with a single `seek`.
- View-graph smoke for `CueMarkerView`: in `normal`, `hovered` (`isHovered=true, isSelected=false`), and `selected` (`isSelected=true, isHovered=true`) states, assert halo opacity is `0.35` for `hovered` only and `0` for the other two.

### UI (`OnlyCueUITests`)

Gherkin acceptance, mirrored as XCUITest cases:

- *Given* the waveform is showing and transport is playing, *when* I press and hold on empty timeline at time T1 and drag to time T2, *then* playback pauses at T1 on press, the playhead follows my cursor, and on release the playhead is at T2 with playback resumed.
- *Given* transport is paused, *when* I click on empty timeline at time T1, *then* the playhead seeks to T1 and transport stays paused.
- *Given* a cue marker is visible, *when* I hover the marker, *then* the `cueMarker-<id>` element remains queryable and the resize-LR cursor is set. (XCUITest cannot assert halo opacity directly; the view-graph smoke above covers that.)
- *Given* a cue marker is selected, *when* I hover it, *then* no halo appears (covered by the view-graph smoke; not asserted in XCUITest).

UI tests that reference `playheadGrabber` are deleted or rewritten against `waveformSeekSurface`.

## Risks and open questions

- **Marker priority regression**: covered by the fallback above; verify during implementation.
- **Accidental scrub on hesitant click**: a click with a few pixels of micro-movement will momentarily pause playback if the user was playing. Acceptable — pause/resume is idempotent in `PlayerEngine` and the user perceives a single click. If complaints surface, raise `DragGesture(minimumDistance:)` from 0 to 2 px (changing the tap-vs-drag boundary only for the seek surface, not for markers).
- **Cursor flicker** at the boundary between the marker hit zone and the surrounding seek surface — both push/pop the system cursor. Today's grabber already pushed `openHand`; net cursor behavior on the new surface is one fewer push.

## Out of scope (filed for later)

- Reworking marker hit-test priority globally (only intervene if the z-order experiment shows markers lose hits).
- Keyboard / touch-bar equivalents for hold-scrub.
- Per-cue color preview in the hover halo (currently uses the marker's resolved color, no preview swatch).

## References

- `docs/data-model.md` — no schema change; this is a pure UI design.
- `OnlyCue/UI/WaveformPlayheadLayer.swift` — primary edit site.
- `OnlyCue/UI/CueMarkersOverlay.swift` — `CueMarkerView` edit site.
- `OnlyCue/UI/ScrubController.swift` — reused, unchanged.
- `OnlyCue/UI/CueMarkersGeometry.swift` — reused for press-location → time conversion.
