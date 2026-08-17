# Mini Player — focus-to-type, title-bar-only drag, resizable width

**Issue:** TBD (miniplayer UX fixes — 3-in-1)
**Date:** 2026-08-17
**Status:** Approved (brainstorming)

Supersedes two constraints of earlier Mini Player specs, deliberately and narrowly:

- `docs/superpowers/specs/2026-08-16-miniplay-design.md` **Decision 5**
  (".nonactivatingPanel — clicking it does not steal focus") is **relaxed**: the
  operator explicitly wants *click-to-focus* so the keyboard drives the panel.
- `docs/superpowers/specs/2026-08-17-miniplayer-keyboard-and-collapse-design.md`
  **non-goal "Changing the panel to a key/activating window"** is **relaxed** for the
  same reason. The other non-goal (no global hotkeys when OnlyCue is not frontmost)
  **still stands** — this spec does not add global hotkeys.

## Problem

Three defects/gaps surfaced in real use of the Mini Player (a floating `NSPanel`):

1. **Keyboard is dead when the main window isn't up.** Shortcuts are delivered by a
   local `NSEvent` key-down monitor (`DocumentView+MiniKeyMonitor`), which only fires
   while OnlyCue is the **active application**. Because the panel is
   `.nonactivatingPanel`, clicking it (or collapsing so only the panel remains) does not
   make OnlyCue active, so Space / ↑ ↓ / ← → / GO / rate keys do nothing. The user's
   mental model is the standard macOS one: **select (click) the Mini Player → keyboard
   shortcuts work.**
2. **Dragging the scrub knob moves the whole window.** The panel sets
   `isMovableByWindowBackground = true`; the progress-bar `DragGesture` does not reliably
   win over background-drag, so scrubbing drags the panel instead of seeking.
3. **Fixed 620-wide panel crushes content.** Width is hard-fixed (620) and the panel is
   not resizable, so long (e.g. CJK) media titles and the CUE/NEXT block are truncated
   (title collapses to "1…"). Users want to widen the panel.

## Goals

1. Clicking (selecting) the Mini Player gives it keyboard focus so all whitelisted
   playback shortcuts work (the existing whitelist/gate/action seam is reused).
2. The scrub bar seeks reliably; the window moves only by its title bar.
3. The panel is horizontally resizable within **660–1000 pt**, height fixed; width is
   remembered. Extra width goes to the title; the CUE/NEXT block stays a fixed width and
   the **current** cue name is always visible (the NEXT/preview name may ellipsize at the
   minimum width).

## Non-goals

- **Global hotkeys** when OnlyCue is not the frontmost app (still out of scope; needs
  Accessibility permission).
- Vertical resize (height stays fixed — the transport row is a fixed height).
- New key bindings, new transport controls, or any `ProjectModel` schema change (window
  width/position live in the frame-autosave `UserDefaults`, not the document).

---

## Feature 1 — Focus-to-type (click the panel → keyboard works)

**Behavior:** clicking anywhere in the Mini Player activates OnlyCue and makes the panel
the key window. Once the app is active, the existing local key-down monitor fires and the
existing `MiniPlaybackGate` / `MiniPlaybackKeymap` / Mini-playback-action seam dispatch the
shortcut exactly as designed in #743. No new key handling logic is added — only the panel
is made focusable.

**Mechanism:**

- The panel becomes **key-capable**: drop `.nonactivatingPanel` from the style mask (or a
  minimal `NSPanel` subclass overriding `canBecomeKey → true`) while keeping
  `isFloatingPanel = true` / `level = .floating` (still always-on-top) and
  `hidesOnDeactivate = false` (survives deactivation). A click now activates OnlyCue and
  focuses the panel.
- **Gate interaction (unchanged):** with the panel key, `documentWindow?.isKeyWindow` is
  `false`, `isFrontmostMiniPanel` is `true`, `panelVisible` is `true` →
  `MiniPlaybackGate.shouldHandle` fires and the monitor handles the key. When the main
  window is the key window instead, the gate yields to the main window's SwiftUI
  shortcuts, as today. The gate's truth table does not change.

**Deliberate consequence (supersedes Decision 5):** clicking any Mini Player control now
takes keyboard focus to OnlyCue — the "drive playback while another app stays frontmost"
property is gone. Accepted: the operator's workflow is Mode B (the Mini Player *is* the
surface they're looking at), not Mode A (a console app frontmost with the Mini as a
non-stealing overlay).

## Feature 2 — Title-bar-only window move

Set `isMovableByWindowBackground = false`. The panel keeps its native `.titled` title bar,
so it still moves by the title bar (system behavior). The scrub `DragGesture` is now the
only drag consumer in the body, so click-to-seek and drag-to-scrub work without moving the
window. No change to the gesture itself.

## Feature 3 — Resizable width (660–1000, height fixed)

- Add `.resizable` to the panel style mask.
- `panel.minSize = (660, H)` and `panel.maxSize = (1000, H)` with the **same** height for
  both, locking vertical size while allowing horizontal resize. `H` is the panel's current
  fixed content height (the hosting view's fitting height).
- Remove the hard `rootView.frame(width: 620)` in the hosting controller so the SwiftUI
  body fills the panel width. `MiniPlayerView.body` already uses
  `.frame(maxWidth: .infinity, alignment: .leading)`, the title/CUE-NEXT already truncate,
  and the progress bar already fills — so the body reflows without structural changes.
  (Design source of truth: Figma "Mini Player — Resize Range" group `607:3185`, three
  variants × min 660 / wide 1000.)
- Width persistence is already handled by `setFrameAutosaveName` (frame incl. width is
  saved to `UserDefaults`); on first launch clamp the restored width into [660, 1000].
- Default/opening width: 660 (the new minimum) rather than 620.

**Reflow priority (matches Figma):** title = flexible (absorbs extra width, ellipsizes when
too narrow); transport, timecode = fixed; CUE/NEXT block = fixed width, current-cue name
always shown, NEXT name ellipsizes at 660.

---

## Components

| Unit | Responsibility |
| --- | --- |
| `MiniPlayerController` (edit) | Key-capable style mask (drop `.nonactivatingPanel` / `canBecomeKey`); `isMovableByWindowBackground = false`; add `.resizable` + min/max size; drop the fixed-width `.frame`; open at 660. |
| `MiniPlayerSize` (new, pure) | `clamp(width:) -> CGFloat` into [660, 1000]; the min/max/default constants. Unit-tested. |
| `MiniPlayerView` (verify) | Confirm body reflows at 660 and 1000 with no overlap; no structural change expected. |

The keyboard whitelist, gate, keymap, and action seam from #743 are **reused unchanged**.

## Testing (TDD)

- **`MiniPlayerSize.clamp`** (pure, unit): width below 660 → 660; above 1000 → 1000;
  in-range unchanged; min/max/default constants are 660/1000/660.
- **Panel configuration** (regression guards on `MiniPlayerController`): the created panel
  is key-capable (`canBecomeKey == true` and style mask does **not** contain
  `.nonactivatingPanel`); `isMovableByWindowBackground == false`; style mask contains
  `.resizable`; `minSize.width == 660`, `maxSize.width == 1000`, `minSize.height ==
  maxSize.height` (height locked); still `isFloatingPanel` / `.floating`.
- **`MiniPlaybackGate`** truth table: unchanged (already covered) — re-run to prove the
  focus change doesn't regress the handle-vs-yield decision.
- The `NSEvent` monitor and click→activate wiring are thin AppKit glue over the pure
  gate/keymap; the app-active precondition is validated by manual smoke test
  (collapse / click panel → Space toggles playback), since `NSApp.isActive` is not
  unit-testable.

## Risks

- Dropping `.nonactivatingPanel` means the Mini Player now activates OnlyCue on click.
  Verify: (a) collapse-to-mini still works and Space/arrows drive playback after a click;
  (b) with the main window also open, clicking the main still gives it focus and its
  shortcuts win (gate yields); (c) the panel still floats above other apps.
- Resizable panel + `NSHostingController`: verify no layout jump or clipping at 660 and
  1000, and that the autosaved width restores clamped on next launch.
- Title-bar-only move must not break the existing click-to-seek / accessibility hit-tests
  on the progress bar (project CLAUDE.md gesture caution).
