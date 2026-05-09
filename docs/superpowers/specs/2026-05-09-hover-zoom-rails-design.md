# Hover-revealed waveform zoom rails

**Status:** approved
**Date:** 2026-05-09
**Epic:** #36 (timeline UX)
**Supersedes:** the bottom-edge `VerticalZoomDragHandle` shipped in PR #67

## Problem

Today the waveform has two zoom dimensions with mismatched affordances:

- **Vertical zoom** — a thin horizontal drag rail glued to the bottom of the waveform (`VerticalZoomDragHandle`). Drag up/down zooms vertical amplitude. Axis-perpendicular placement is counter-intuitive.
- **Horizontal zoom** — *no* on-screen control. Only ⌘= / ⌘- / ⌘0 keyboard shortcuts and trackpad pinch. Discoverability is zero for new users.

Both controls also occupy or could occupy chrome that competes with the waveform itself.

## Goal

Give each zoom axis a discoverable, axis-aligned, continuous-drag control that stays out of the way at rest. Keep all existing keyboard shortcuts and pinch behavior unchanged.

## Design

### Layout & visibility

Two rails overlaid on the waveform area, both invisible at rest:

- **Vertical zoom rail** — 14pt wide, full waveform height, attached to the right edge of the waveform area (inside the existing 8pt horizontal padding so it overlays padding rather than waveform pixels).
- **Horizontal zoom rail** — ~14pt tall, full waveform width, attached to the bottom edge (where the old `VerticalZoomDragHandle` lived).

Visibility behavior:

- Opacity 0 at rest.
- On pointer-enter of the waveform area, both rails fade in together (~120ms).
- On pointer-exit, both fade out together (~200ms).
- While a drag is in progress, the rail being dragged stays visible even if the cursor leaves it.
- **First-launch hint:** on the very first waveform load of a session, both rails fade in for ~1.5s then fade out, so new users see them at least once. Tracked via a session-scoped flag (not persisted).

### Visual & content

Each rail is a thin translucent surface:

- Resting fill (when revealed): `Color.secondary.opacity(0.18)`.
- Hover-of-rail fill: `Color.secondary.opacity(0.40)`.

Each rail shows a single **magnifier-glyph zoom badge** with the live zoom level:

- Vertical rail: SF Symbol `magnifyingglass` + e.g. `2.0×`, centered vertically, read left-to-right.
- Horizontal rail: `magnifyingglass` + e.g. `1.0×`, anchored to the right end of the strip.

No discrete `＋`/`−` buttons. Stepping stays on keyboard shortcuts.

### Interaction

- **Vertical rail** — drag up = zoom in, drag down = zoom out. Cursor: `resizeUpDown`. Reuses `WaveformVerticalZoomController.applyDrag(translation:baseline:)` from PR #67.
- **Horizontal rail** — drag right = zoom in, drag left = zoom out, anchored on the cursor's x-fraction so zoom centers on the pointer. Cursor: `resizeLeftRight`. Reuses `WaveformZoomController.setZoom(_:anchorFraction:viewportWidth:scrollOffset:)` (the same math the trackpad pinch path uses).
- **Double-click the badge** on either rail = reset that axis (`applyZoomReset()` / `verticalZoom.reset()`).
- ⌘= / ⌘- / ⌘0, ⌘⌥= / ⌘⌥- / ⌘⌥0, trackpad pinch, and scroll behavior are **unchanged**.

## Files

- **New:** `OnlyCue/UI/WaveformZoomRail.swift` — one view parameterized by axis (`.vertical` / `.horizontal`), takes the controller plus an "apply drag" closure so a single view serves both axes.
- **Edit:** `OnlyCue/UI/WaveformContainer.swift` — replace the `VStack { waveformBody; VerticalZoomDragHandle }` with a `ZStack` that overlays both rails on top of `waveformBody`. Add `@State` for `isHoveringWaveform` and `hasShownFirstLaunchHint`.
- **Delete:** `OnlyCue/UI/VerticalZoomDragHandle.swift` (superseded).
- **Tests:** rename `VerticalZoomDragHandleTests` → `WaveformZoomRailTests`; add a horizontal-axis test that exercises the `setZoom(_:anchorFraction:...)` path with a synthetic drag translation.

## Non-goals

- No new zoom math. Both rails reuse existing controller methods.
- No persistent first-launch flag — session-scoped is enough; the rails are also revealed by any future hover.
- No `＋`/`−` buttons. The minimal aesthetic is intentional; discrete stepping is the keyboard's job.
- No change to the playhead, cue markers, or scroll-position anchoring.

## Verification

- Manual: launch app, import media, observe rails fade in on first load, fade out, then re-appear on hover. Drag each rail and confirm continuous zoom; badge updates live.
- Manual: ⌘=, ⌘-, ⌘0, ⌘⌥=, ⌘⌥-, ⌘⌥0, and trackpad pinch all still work.
- Tests: `WaveformZoomRailTests` covers vertical-drag math (existing) and a new horizontal-drag case anchored on a synthetic cursor x-fraction.
- Spec section: implements `docs/` UX direction for epic #36 (timeline UX).
