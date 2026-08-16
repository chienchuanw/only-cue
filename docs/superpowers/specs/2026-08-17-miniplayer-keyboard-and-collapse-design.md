# Mini Player — keyboard shortcuts + collapse-to-mini

**Issue:** #743 (`feat: miniplayer mode`)
**Date:** 2026-08-17
**Status:** Approved (brainstorming)

Supersedes two constraints of `docs/superpowers/specs/2026-08-16-miniplay-design.md`:
its Decision 5 ("does not steal focus") is *kept*, but the MVP out-of-scope note and
its line "belongs to its document window (closes with it)" are **relaxed** — the Mini
Player now survives a main-window collapse and gains playback keyboard control.

## Problem

The Mini Player is a floating `.nonactivatingPanel` that mirrors playback but has **no
keyboard control**: playback shortcuts live as hidden SwiftUI buttons in `DocumentView`'s
`.background` and only fire while the main document window is key. When the operator
collapses to the Mini Player (main window minimized, behind, or dismissed), there is no
key document window, so Space / arrows / GO / rate keys are dead. Additionally, hitting
the main window's close button today tears down the document and the engine, stopping
playback — the operator cannot "minimise to a small player" and keep going.

## Goals

1. Playback keyboard shortcuts work while the Mini Player is the active surface.
2. The main window's close button collapses the app into the Mini Player (hide, not
   destroy); playback continues; the document is never silently discarded.
3. A clear, always-safe path back to the main window and to truly closing the document.

## Non-goals

- Global hotkeys when OnlyCue is **not** the frontmost app (needs Accessibility
  permission; explicitly out of scope).
- New key bindings for prev/next **song** (kept deferred, per #753).
- Editing shortcuts in the Mini Player (add-cue `M`, cue-type digits `0`–`9`).
- Changing the panel to a key/activating window (Decision 5 of the mini spec stands).
- A global follow-frontmost panel, or multi-document collapse coordination beyond the
  frontmost-gate already in place.

---

## Feature 1 — Playback keyboard shortcuts in the Mini Player

### Whitelisted actions

Only pure playback/navigation `KeymapAction`s are honored (resolved through the existing
`KeymapStore`, so user re-bindings apply in the Mini Player too):

| Action | Default key | Reaches |
| --- | --- | --- |
| `playPause` | Space | `engine.toggle()` |
| `jumpBack` / `jumpForward` | ← / → | `engine.seek(by: ∓1s)` |
| `stepPrevCue` / `stepNextCue` | ↑ / ↓ | seek to prev/next cue (type-filtered) |
| `go` | Return | Show-mode GO (seek + play) |
| `playbackRateUp` / `Down` / `Reset` | `]` / `[` / `\` | `engine` rate nudges |

Excluded: `addCue` (`M`), cue-type digits — editing, not playback.

### Interception mechanism

A local `NSEvent` key-down monitor, installed by `MiniPlayerController` while its panel is
visible and removed on hide/close. On each key-down it runs a **pure decision**:

1. **Gate (Approach A — yield to the main window):** handle only when
   - this controller's panel is visible **and** it is the frontmost document's Mini Player
     (reuse the existing frontmost gate), **and**
   - the current key window is **not** a main document window (main window is
     minimized / hidden / behind).
   Otherwise return the event unchanged, so the main window's existing SwiftUI shortcuts
   (which already yield to inline text fields) handle it.
2. **Resolve:** match the event's key + modifiers against `KeymapStore.keymap`; accept
   only the whitelist above.
3. **Dispatch + consume:** invoke the shared Mini playback action (below), honoring
   existing gates (LTC interlock disables rate keys; `go` only in Show mode; a media item
   must be loaded), then **return `nil`** to consume the event (no system beep).
4. **No match:** return the event unchanged.

### Shared action seam

Extract one small Mini playback-action type holding `engine` / `document` / `context`,
exposing `playPause`, `jump(_:)`, `stepCue(_:)`, `go`, `rate(_:)`. **Both** the
`MiniPlayerView` button callbacks **and** the key monitor call it, so button and keyboard
behavior cannot drift. It reuses the same underlying seams the buttons already use
(`engine`, `MediaItem.cue(steppingFrom:)`, `CueCommands`, `showGoDecision`).

---

## Feature 2 — Collapse to Mini (hide-not-close)

Core invariant: **while a document is open, it never has zero visible surfaces**, and an
unsaved document is never silently discarded.

### Collapse

When the Mini Player is visible and the operator hits the main window's close button or
⌘W, **hide the main window** (`orderOut`) instead of closing the document. `DocumentView`,
`engine`, and `document` stay alive; playback continues; the Mini Player takes over
keyboard control (per Feature 1's gate — no key document window). When the Mini Player is
**not** visible, the close button behaves normally (closes the document, with the standard
save prompt).

Implementation: attach an `NSWindowDelegate` to the document window; `windowShouldClose`
returns `false` and orders the window out **iff** the Mini Player is visible; otherwise
returns `true` (default close). (The app already uses an `NSWindowDelegate` for the
welcome window, so the pattern exists.)

### Restore

- Closing the Mini Player (its own close) restores the main window **iff** the main window
  is hidden; otherwise it just closes the Mini Player (current behavior).
- `⌘⌥M` / `View → Mini Player` toggle: when the Mini Player is visible and the main window
  is hidden, the toggle restores the main window and hides the Mini Player (equivalent to
  closing the Mini Player).
- New menu item **`View → Show Main Window`**, enabled only while the main window is
  hidden, orders it back to front.

### True close

Restore the main window, then ⌘W with the Mini Player off — the standard document close
(save prompt intact). No collapse path ever bypasses the save flow.

### State

`DocumentView` tracks whether its main window is collapsed (hidden). This drives the
`Show Main Window` menu item's enabled state and the restore-vs-close-mini decision. The
collapse flag is per-window working state.

---

## Components

| Unit | Responsibility |
| --- | --- |
| `MiniPlaybackKeymap` (new, pure) | Map a key chord → whitelisted playback action (or nil). Unit-tested. |
| `MiniPlaybackGate` (new, pure) | Decide handle-vs-yield from (panelVisible, isFrontmostMini, mainWindowIsKey). Unit-tested. |
| Mini playback-action seam (new) | `engine`/`document`/`context` → playback actions; shared by buttons + monitor. |
| `MiniPlayerController` (edit) | Install/remove the key-down monitor with the panel; own the collapse/restore of the main window. |
| Document-window delegate (new/edit) | `windowShouldClose` → collapse when Mini visible, else default. |
| `DocumentView` + `View` menu (edit) | Collapse state, `Show Main Window` command, ⌘⌥M restore semantics. |

## Testing

- **`MiniPlaybackKeymap`**: whitelist chords resolve to the right action; excluded/unknown
  chords → nil; custom `KeymapStore` bindings resolve.
- **`MiniPlaybackGate`**: truth table over (panelVisible × isFrontmostMini × mainWindowIsKey)
  → handle only in the intended cell; everything else yields.
- **Collapse decision** (pure): `windowShouldClose` outcome from (miniVisible) →
  hide vs default-close; restore-mini decision from (mainWindowHidden).
- Action dispatch reuses already-tested engine/`CueCommands` seams.
- The `NSEvent` monitor and `orderOut`/delegate wiring are thin glue over the pure
  decisions; covered by targeted checks where practical, not exhaustive UI automation.

## Risks

- SwiftUI `DocumentGroup` + a custom `windowShouldClose` that hides instead of closes: a
  hidden-but-open document still appears in the Window menu; verify ⌘W/quit/save flows
  behave. Mitigated by keeping the document fully alive (no ownership move) and only
  intercepting when the Mini Player is visible.
- Multi-document: each window keeps its own engine; the frontmost gate scopes both the key
  monitor and collapse to the frontmost document, as today.
