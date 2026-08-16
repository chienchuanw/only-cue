# Mini Player (macOS) — design

**Status:** approved (grill/brainstorm 2026-08-16 in zh-Hant; Figma approved 2026-08-16)
**Figma:** file `NhH2957iKQ8b581x3gI3Wk`, page "Screens", section "Mini Player (macOS)"
— Cue Mode `581:3020`, Show Mode `583:3020`, Empty `583:3058`.

## Problem & goal

Live operators need to drive cue playback without the full 1280-wide document
window in the way. Mini Player is a compact, **always-on-top floating control
bar** that mirrors and controls the active document's playback.

## Confirmed decisions

1. **Form:** a floating, always-on-top **wide horizontal control bar** for the
   live operator (not an audience/projection view).
2. **Binding:** **one Mini Player per document window**, sharing that window's
   existing `PlayerEngine` directly. Zero refactor, always in sync. (A future
   "single global panel that follows the frontmost document" would need an
   `ActiveDocumentRegistry`; explicitly out of scope for the MVP.)
3. **Displays:** media name (title bar), big SMPTE **timecode + framerate**,
   **current cue** (number + name + type-color dot), **next cue** (number + name
   + countdown + dot).
4. **Controls:** play/pause, previous cue, next cue, and **GO**. GO appears
   **only when the document is in Show Mode** and honours the document's
   `showGoTypeID`; prev/next mirror the main window's stepping semantics. Mini
   Player is a **pure mirror** — it never changes the editor mode.
5. **Window behaviour:** `NSPanel` (`.nonactivatingPanel`, floating window level)
   that floats above other apps and does not steal focus when clicked; **fixed
   compact size** (620×104pt); remembers **position and visibility**.
6. **Invocation:** `View → Mini Player` (checkable toggle) + shortcut **⌘⌥M**;
   closing the panel = hiding Mini Player; visibility persisted.
7. **Lifecycle / empty state:** belongs to its document window (closes with it);
   when there is no active media, shows an empty state ("No media loaded",
   `00:00:00:00`, "No active cue") with the transport disabled; follows the
   document when the active media changes.
8. **Look / reuse:** dark, `DS` tokens (consistent with ADR-029 dark-only spirit);
   reuse `TransportBar` countdown/tempo math, `MediaItem.activeCue`/stepping, and
   the existing timecode formatting; **new compact UI** (not the main
   `TransportControls` bar). Circular transport buttons; GO as a rounded pill.
9. **Platform:** macOS only (this stage).

**Out of scope (MVP):** waveform/scrub, media switching, volume, playback-rate,
cue editing, switching Cue/Show mode from Mini Player, a global follow-frontmost
panel, Windows.

## Architecture

- **`MiniPlayerModel` (pure, testable):** given `currentTime`, the active
  `MediaItem` (or nil), its `cues`, `cuePointTypes`, `timecodeSettings`,
  `editorMode`, and `showGoTypeID`, derive the view state: timecode string,
  framerate label, current-cue label + color, next-cue label + color + countdown
  string, `isEmpty`, and `showsGo`. This isolates all display logic from the
  window/UI so it can be unit-tested against known inputs (reusing `TransportBar`
  + `MediaItem` + `Timecode` helpers).
- **`MiniPlayerView` (SwiftUI):** the compact bar, consuming `MiniPlayerModel`
  and the shared `PlayerEngine`; buttons call `engine.toggle()` and the same
  prev/next/GO seams the main window uses (`DocumentView+ShowGo`).
- **`MiniPlayerController` (AppKit):** owns the `NSPanel`
  (`.nonactivatingPanel`, `.floating` level, fixed size), hosts `MiniPlayerView`
  via `NSHostingController`, persists frame origin + visibility
  (`@AppStorage`/`UserDefaults`), and is created/destroyed with its document
  window. Follows the existing `AppDelegate` NSWindow pattern.
- **Menu/command:** a `View → Mini Player` toggle (checkmark reflects visibility)
  bound to ⌘⌥M, routed to the frontmost document's controller (mirrors existing
  command patterns, e.g. Hide Inspector).

## Verification strategy

- **Unit tests (TDD, primary):** `MiniPlayerModelTests` — timecode formatting per
  framerate incl. drop-frame; current/next cue selection and labels; countdown
  formatting; empty state when no media / no cues; `showsGo` true only in Show
  mode; GO/stepping respect `showGoTypeID`. Written red-first.
- **XCUITest (behavioral/screenshot):** open Mini Player from a seeded document,
  assert the panel appears, play/pause toggles engine state, and capture a
  dark-mode screenshot for the Figma↔app check (Cue / Show / Empty states).
- macOS-only; dark-only surface; consumes `DS.*` tokens (TokenConformance).

## Milestones

- **M1 — model + view:** `MiniPlayerModel` (TDD) + `MiniPlayerView` compact UI.
- **M2 — window + command:** `MiniPlayerController` (NSPanel) + `View` menu toggle
  + ⌘⌥M + position/visibility persistence + per-document lifecycle.
- **M3 — polish:** empty-state, Show-mode GO wiring, screenshot baseline, a11y.

> **Note:** the "closes with its document window" constraint in §Constraints is relaxed by `docs/superpowers/specs/2026-08-17-miniplayer-keyboard-and-collapse-design.md` (#743).
