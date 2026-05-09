# Waveform Zoom Magnifier — Design

**Date:** 2026-05-09
**Status:** Approved (brainstorming)
**Supersedes:** PR [#74](https://github.com/chienchuanw/only-cue/pull/74) (hover-revealed zoom rails) and PR [#81](https://github.com/chienchuanw/only-cue/pull/81) (rail polish).
**Spec section:** continues epic [#36](https://github.com/chienchuanw/only-cue/issues/36) (timeline UX polish), vertical-zoom + horizontal-zoom on-screen surface.

## Goal

Replace the two gray hover-revealed zoom rails (vertical on the right edge, horizontal on the bottom) with a single hover-revealed magnifier control at the bottom-right corner of the waveform that exposes BOTH horizontal and vertical zoom via a two-axis click-and-drag gesture. Reduce visual surface area to one affordance, retain discoverability through hover-reveal + first-launch hint, keep all existing zoom math (controllers, sensitivity, scroll-anchor) untouched.

## Non-goals

- Changing zoom math, controllers, or sensitivity (`dragPixelsPerStep = 60` is reused).
- Removing keyboard shortcuts (`⌘=` / `⌘-` / `⌘0`, `⌘⌥=` / `⌘⌥-` / `⌘⌥0`) or trackpad pinch.
- Customizable sensitivity, scroll-wheel-on-magnifier, or Touch Bar surface.
- Preserving cursor-x-anchored horizontal zoom from the bottom rail — the magnifier sits in a fixed corner, so horizontal anchor is hard-coded to `0.5` (center).
- Per-axis double-click reset (the rails had it; the magnifier doesn't — single double-click resets both axes; per-axis reset stays available via keyboard).

## Architecture

Two new files plus a dispatch helper, three deletions:

- **`OnlyCue/UI/WaveformZoomMagnifier.swift`** (new) — overlay view. Owns no zoom math.
- **`OnlyCue/UI/WaveformContainer+Magnifier.swift`** (new) — extension on `WaveformContainer` that wires the magnifier's drag callback to the two existing controllers.
- **`OnlyCue/UI/MagnifierAxisLock.swift`** (new) — pure helper that decides which axis "wins" when Shift is held.
- **`OnlyCue/UI/WaveformContainer.swift`** — `loaded(peaks:)` body switches from `ZStack { waveformBody; verticalRail; horizontalRail }` to `waveformBody.overlay(alignment: .bottomTrailing) { magnifier.padding(8) }`. The hover/hint plumbing (`isHoveringWaveform`, `hintShowing`, `FirstLaunchHintTracker`) is kept verbatim.
- **Deletions**: `OnlyCue/UI/WaveformZoomRail.swift`, `OnlyCue/UI/WaveformContainer+ZoomRails.swift`, `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift`.

The two zoom controllers (`WaveformZoomController`, `WaveformVerticalZoomController`) and their `applyDrag(...)` methods are unchanged.

## Components

### `WaveformZoomMagnifier`

Single SwiftUI view. Renders an `Image(systemName: "magnifyingglass")` glyph plus a two-line `Text` badge (`H 2.0× / V 1.5×`) on `.ultraThinMaterial` capsule background. Owns three pieces of local state: `dragBaseline: (h: CGFloat, v: CGFloat)?`, `axisLockState: MagnifierAxisLock.State`, `isHovering: Bool`.

Visibility: `opacity(isVisible || dragBaseline != nil ? 1 : 0)` — same `isVisible || activeDrag` pattern the rails used. `isVisible` is the container's `isHoveringWaveform || hintShowing`.

Inputs (constructor):

- `horizontalZoom: CGFloat`, `verticalZoom: CGFloat` (for live badge display).
- `isVisible: Bool`.
- `onDrag: (MagnifierDrag) -> Void` where `MagnifierDrag` carries `(translationX, translationY, hBaseline, vBaseline, axisLock: MagnifierAxisLock.Resolution)`.
- `onResetRequested: () -> Void`.

Gestures:

- `DragGesture(minimumDistance: 0)` — captures both baselines on first `onChanged`, computes axis-lock resolution via `MagnifierAxisLock.resolve(...)` (passing in `NSEvent.modifierFlags.contains(.shift)`), forwards the drag info to the closure.
- `onTapGesture(count: 2)` — calls `onResetRequested`.
- `.onHover { ... }` — toggles `NSCursor.crosshair.push()` / `NSCursor.pop()` and `isHovering` for the capsule fill.

### `WaveformContainer+Magnifier` (extension)

```swift
extension WaveformContainer {
    var magnifier: some View {
        WaveformZoomMagnifier(
            horizontalZoom: zoom.zoom,
            verticalZoom: verticalZoom.zoom,
            isVisible: isHoveringWaveform || hintShowing,
            onDrag: applyMagnifierDrag,
            onResetRequested: applyMagnifierReset
        )
    }

    private func applyMagnifierDrag(_ drag: MagnifierDrag) {
        guard viewportWidth > 0 else { return }
        var offset = scrollOffset
        zoom.applyDrag(
            translation: drag.axisLock.effectiveX,
            baseline: drag.hBaseline,
            anchorFraction: 0.5,
            viewportWidth: viewportWidth,
            scrollOffset: &offset
        )
        scrollOffset = offset
        pinchBaseline = zoom.zoom
        verticalZoom.applyDrag(translation: drag.axisLock.effectiveY, baseline: drag.vBaseline)
        syncAnchorFromOffset(viewportWidth: viewportWidth)
    }

    private func applyMagnifierReset() {
        applyZoomReset()           // existing helper, resets horizontal + scrollOffset + leadingAnchor
        verticalZoom.reset()
    }
}
```

The `0.5` horizontal-anchor literal is hard-coded with a one-line `// magnifier sits in a fixed corner — center-anchor is the only sensible default` comment.

### `MagnifierAxisLock`

Pure helper. The only piece of behavior with branching logic worth automated coverage.

```swift
enum MagnifierAxisLock {
    /// Sampled at drag start. Once `.locked` is decided, it sticks for the
    /// rest of the drag — preventing axis flip mid-drag.
    enum State {
        case unresolved
        case unlocked
        case lockedHorizontal
        case lockedVertical
    }

    /// Per-tick resolution. The view holds `state` and updates it from
    /// `resolve(...)`'s return value. `effectiveX` / `effectiveY` are what
    /// the container forwards to the controllers.
    struct Resolution {
        let nextState: State
        let effectiveX: CGFloat
        let effectiveY: CGFloat
    }

    /// `decisionThreshold = 10` (points). Below that, both axes are passed
    /// through unchanged regardless of `isShiftHeld` — the user hasn't moved
    /// far enough to declare intent. At/above threshold, if `isShiftHeld`,
    /// the axis with greater |translation| wins and the other is zeroed.
    static let decisionThreshold: CGFloat = 10

    static func resolve(
        translationX: CGFloat,
        translationY: CGFloat,
        isShiftHeld: Bool,
        currentState: State
    ) -> Resolution
}
```

Three behaviors locked in the pure function:

1. **No shift**: `effectiveX = translationX`, `effectiveY = translationY`, state stays `.unlocked` once it leaves `.unresolved`.
2. **Shift, below threshold**: pass-through (unresolved). Don't lock until the user actually moves far enough to declare intent.
3. **Shift, at/above threshold, unresolved**: lock to whichever axis has greater absolute translation. Once locked, the locked-out axis is forced to `0` for the rest of the drag (state stays `.lockedHorizontal` / `.lockedVertical` even if the user releases Shift mid-drag — the lock is a one-shot decision per drag).

Releasing the drag resets the view's `dragBaseline` to nil and `axisLockState` to `.unresolved`.

## Data flow

```
User clicks-and-drags magnifier
  ↓
DragGesture.onChanged(value)
  ↓
WaveformZoomMagnifier:
  - if dragBaseline == nil → capture (zoom.zoom, verticalZoom.zoom)
  - resolution = MagnifierAxisLock.resolve(
        translationX: value.translation.width,
        translationY: value.translation.height,
        isShiftHeld: NSEvent.modifierFlags.contains(.shift),
        currentState: axisLockState)
  - axisLockState = resolution.nextState
  - onDrag(MagnifierDrag(
        translationX: resolution.effectiveX,
        translationY: resolution.effectiveY,
        hBaseline: dragBaseline.h,
        vBaseline: dragBaseline.v,
        axisLock: resolution))
  ↓
WaveformContainer.applyMagnifierDrag(drag):
  - zoom.applyDrag(translation: drag.translationX, ..., anchorFraction: 0.5, ...)
  - verticalZoom.applyDrag(translation: drag.translationY, baseline: drag.vBaseline)
  - syncAnchorFromOffset(...)
  ↓
SwiftUI re-renders: waveform reflows + magnifier badge updates to live H/V values.
```

## Visual specs

| Element | Spec |
|---|---|
| Glyph | `Image(systemName: "magnifyingglass")`, `.body` weight, `.secondary` foreground |
| Badge | Two-line, right-aligned, `.caption2.monospacedDigit()` (`"H 2.0×"` / `"V 1.5×"`), `.secondary` foreground |
| Container | `HStack(spacing: 4) { glyph; badge }` inside `Capsule().fill(.ultraThinMaterial)` |
| Padding | 6pt horizontal, 3pt vertical inside capsule; 8pt from bottom-right corner of waveform |
| Cursor on hover | `NSCursor.crosshair` (signals two-axis manipulation, distinct from rail's resize cursors) |
| Resting opacity | 0 (fully invisible) |
| Visible opacity | 1.0 (no resting visibility) |
| Hover-fill brighten | Capsule background → `.thinMaterial` while hovering (slightly more opaque) |
| Fade-in | 120ms ease-in-out |
| Fade-out | 200ms ease-in-out |
| First-launch hint | 1.5s reveal on first waveform load (existing `FirstLaunchHintTracker` plumbing) |

## Error handling

Unchanged. Drag is a no-op when `viewportWidth <= 0` (existing guard in `applyMagnifierDrag`). Zoom controllers handle their own clamping (1×–16× horizontal, 1×–8× vertical).

## Testing

### Pure-function tests (new `OnlyCueTests/MagnifierAxisLockTests.swift`)

Six tests covering all decision branches:

1. `noShift_returnsUnlockedPassThrough` — `(translationX: 30, translationY: 5, isShiftHeld: false, .unresolved)` → `effectiveX = 30, effectiveY = 5, nextState = .unlocked`.
2. `shift_belowThreshold_passThroughAndStaysUnresolved` — `(5, 3, true, .unresolved)` → both axes pass through, `nextState = .unresolved`.
3. `shift_atThreshold_horizontalDominant_locksHorizontal` — `(15, 4, true, .unresolved)` → `effectiveX = 15, effectiveY = 0, nextState = .lockedHorizontal`.
4. `shift_atThreshold_verticalDominant_locksVertical` — `(4, 15, true, .unresolved)` → `effectiveX = 0, effectiveY = 15, nextState = .lockedVertical`.
5. `shift_alreadyLockedHorizontal_keepsLock_evenIfShiftReleased` — `(20, 30, false, .lockedHorizontal)` → `effectiveX = 20, effectiveY = 0, nextState = .lockedHorizontal`. (Lock is one-shot per drag — releasing Shift mid-drag does NOT release the lock.)
6. `shift_alreadyLockedVertical_keepsLock` — symmetric to #5.

### Container-dispatch tests (new `OnlyCueTests/WaveformZoomMagnifierTests.swift`)

Four tests covering the dispatch helper through the two real controllers:

1. `applyMagnifierDrag_pureHorizontal_zoomsHorizontalOnly_andAnchorsAtCenter` — drag `(translationX: 60, translationY: 0, hBaseline: 1.0, vBaseline: 1.0)` → horizontal zoom = 1.5×, vertical zoom = 1.0×, scrollOffset reflects center-anchor.
2. `applyMagnifierDrag_pureVertical_zoomsVerticalOnly` — drag `(0, -60, 1.0, 1.0)` → horizontal stays 1.0×, vertical = 1.5×.
3. `applyMagnifierDrag_diagonal_appliesBoth` — drag `(60, -60, 1.0, 1.0)` → horizontal = 1.5×, vertical = 1.5×.
4. `applyMagnifierReset_resetsBothAxes` — preset zoom to (4×, 4×), call reset → both back to 1.0×, scrollOffset = 0, leadingAnchor = 0.

These tests deliberately exercise the dispatch in `WaveformContainer+Magnifier` (the `applyMagnifierDrag` helper) rather than only the pure axis-lock logic — they're the regression-net for "did we break the wiring through the controllers".

### Migration

The 6 horizontal-drag tests in `WaveformZoomRailHorizontalDragTests.swift` are deleted along with the rail. Their coverage is preserved by tests #1 and #3 in `WaveformZoomMagnifierTests` (same controller seam, same expected outputs — just driven through the magnifier dispatch instead of the rail dispatch).

### XCUITest

Deferred per established harness-flakiness precedent (10 consecutive PRs).

## Acceptance (Gherkin)

```gherkin
Scenario: Magnifier reveals on hover
  Given the user has imported a media file
  And the user is not hovering the waveform
  When the user moves the cursor over the waveform
  Then the magnifier appears in the bottom-right corner with H/V zoom badges
  And no gray rails are visible

Scenario: Two-axis drag zooms both axes
  Given the magnifier is visible
  When the user click-and-drags the magnifier diagonally
    "translation: (+60pt, -60pt)"
  Then horizontal zoom multiplies by 1.5×
  And vertical zoom multiplies by 1.5×
  And the badge updates live during the drag

Scenario: Shift-lock pins the dominant axis
  Given the magnifier is visible
  And the user has begun a drag with Shift held
  When the user moves predominantly horizontally past the 10pt threshold
  Then only the horizontal zoom changes for the rest of the drag
  And vertical zoom stays at its baseline

Scenario: Double-click resets both axes
  Given the user has zoomed both axes
  When the user double-clicks the magnifier
  Then horizontal zoom returns to 1.0×
  And vertical zoom returns to 1.0×
  And scrollOffset returns to 0

Scenario: Keyboard shortcuts continue to work
  Given the magnifier is visible
  When the user presses ⌘= (or ⌘⌥=)
  Then horizontal (or vertical) zoom changes by one 1.5× step
  And the magnifier badge reflects the new value
```

## Risks / Notes

- **Center-anchor regression for horizontal zoom**: today's bottom rail anchors horizontal zoom on the cursor's x-fraction (zoom centers on what the user is pointing at). The magnifier sits in a fixed corner with no meaningful cursor x to use, so anchor is hard-coded to `0.5`. Trackpad pinch keeps cursor-anchored behavior. Documented in code with an inline comment.
- **Shift-lock decision is sampled, not continuous**: once locked, the lock holds for the whole drag, even if Shift is released mid-drag. This is a deliberate UX choice — toggling axes mid-drag would be surprising. Tested in case #5 / #6 above.
- **Axis-lock threshold (10pt)** is a magic number. If user feedback says it feels too sticky or too loose, tune the constant — not a controller change.
- **First-launch hint copy unchanged** — the hint just reveals the magnifier for 1.5s. No tooltip or explainer; the magnifier glyph is the explanation.

## Out of scope (deferred)

- Customizable per-axis sensitivity.
- Cursor x-anchored horizontal zoom from the magnifier (would require coupling magnifier position to a cursor sample, which contradicts "fixed corner").
- Per-axis right-click reset menu.
- Touch Bar / scroll-wheel zoom on the magnifier.
- Animation flourishes during drag (the badge update is the only feedback; no glyph rotation, ripple, etc.).

## File-by-file change summary

| File | Change |
|---|---|
| `OnlyCue/UI/WaveformZoomMagnifier.swift` | **Create** — overlay view |
| `OnlyCue/UI/MagnifierAxisLock.swift` | **Create** — pure axis-lock helper |
| `OnlyCue/UI/WaveformContainer+Magnifier.swift` | **Create** — `magnifier` computed property + `applyMagnifierDrag` + `applyMagnifierReset` |
| `OnlyCue/UI/WaveformContainer.swift` | **Modify** — `loaded(peaks:)` body: replace `ZStack` with `.overlay(alignment: .bottomTrailing)` |
| `OnlyCue/UI/WaveformZoomRail.swift` | **Delete** |
| `OnlyCue/UI/WaveformContainer+ZoomRails.swift` | **Delete** |
| `OnlyCueTests/MagnifierAxisLockTests.swift` | **Create** — 6 pure-function tests |
| `OnlyCueTests/WaveformZoomMagnifierTests.swift` | **Create** — 4 dispatch-through-controllers tests |
| `OnlyCueTests/WaveformZoomRailHorizontalDragTests.swift` | **Delete** — coverage preserved by new tests |

Net: +5 files, -3 files, 1 modification.
