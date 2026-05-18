# Menu Bar Reorganization — Design

Date: 2026-05-18
Status: Approved
Scope: Reorganize + rename. No new functionality, no removed functionality.

## Problem

The `View` menu (`CommandGroup(after: .sidebar)` in `OnlyCue/App/AppCommands.swift`)
is overloaded with items that are not view operations:

1. **Cue-editing commands** — Snap to Playhead/Beat/Bar, Duplicate at Playhead,
   Nudge Back/Forward. These mutate the project model via `CueCommands`; they are
   not view state.
2. **"Pause at Each Cue"** — a playback-behavior toggle, sitting among waveform
   zoom controls and display toggles.

This produces a long, semantically incoherent View menu and gives cue
manipulation no discoverable home.

## Goals

- Cue-manipulation commands get a dedicated top-level `Cue` menu.
- `Pause at Each Cue` moves to the `Playback` menu next to the speed controls.
- Cue command labels are shortened now that the enclosing menu is named "Cue".
- Zero behavior change: shortcuts, notifications, accessibility identifiers, and
  every label asserted by UI tests are preserved.

## Non-Goals

- No new menu items or commands.
- No removed commands.
- No changes to `Keymap`, `KeymapStore`, or `KeymapAction`.
- No changes to `NotificationCenter` notification names.
- No changes to `Settings` scene, File menu, or Tools menu.

## Target menu structure

```
File ──────────────────────────  (unchanged)
  Import Media…
  Export Cues…
  ───
  New from Template…
  Save Template As…
  Load Template…

View ──────────────────────────  (cue-edit block + pause toggle removed)
  Zoom In / Zoom Out / Actual Size
  ───
  Zoom In Vertically / Zoom Out Vertically / Actual Vertical Size
  ───
  Show Notes Overlay
  Show Timeline Breakdown
  Show Tempo Grid

Cue  ◄── NEW CommandMenu, declared after the View CommandGroup
  Duplicate at Playhead
  Nudge Back
  Nudge Forward
  ───
  Snap to Playhead
  Snap to Nearest Beat
  Snap to Nearest Bar

Playback ──────────────────────
  Speed Up / Slow Down / Reset Speed   (labels frozen)
  ───
  Pause at Each Cue              ◄── moved here from View

Tools ─────────────────────────  (unchanged)
  Manage Types…
  ───
  Edit Note Overlay Appearance…
  ───
  OSC Monitor…
  Timecode Settings…
```

## Label renames

Applied only to the cue-editing items (none are referenced by UI test title —
verified via `grep` over `OnlyCueUITests/`):

| Old label                              | New label             |
|----------------------------------------|-----------------------|
| Duplicate Cue at Playhead              | Duplicate at Playhead |
| Nudge Selected Cue Back                | Nudge Back            |
| Nudge Selected Cue Forward             | Nudge Forward         |
| Snap Selected Cue to Playhead          | Snap to Playhead      |
| Snap Selected Cues to Nearest Beat     | Snap to Nearest Beat  |
| Snap Selected Cues to Nearest Bar      | Snap to Nearest Bar   |

Rationale: inside a menu named "Cue", repeating "Cue"/"Selected Cue(s)" in every
item is redundant. Selection semantics are implied by menu context, matching
Apple HIG precedent (Finder "Duplicate", not "Duplicate File").

`Pause at Each Cue` keeps its exact label (it moves menus, not text).
All `Playback` speed labels (`Speed Up`, `Slow Down`, `Reset Speed`) are frozen
because `OnlyCueUITests/PlaybackSpeedUITests.swift` asserts on them by title.

## Implementation

Single file: `OnlyCue/App/AppCommands.swift`.

1. From `CommandGroup(after: .sidebar)`, delete the trailing block: the final
   `Divider()` plus the six snap/duplicate/nudge buttons, and the
   `Toggle("Pause at Each Cue", isOn: $pauseAtEachCue)` plus its preceding
   `Divider()`. The display-toggle group (Notes Overlay, Timeline Breakdown,
   Tempo Grid) stays.
2. Add a new `CommandMenu("Cue")` declared after the `CommandGroup(after:
   .sidebar)` and before `CommandMenu("Playback")`, containing the six cue
   commands with their new labels, ordered as in the target structure, with one
   `Divider()` between the duplicate/nudge group and the snap group. Each button
   keeps its existing `NotificationCenter.post` and `.keyboardShortcut(shortcut(…))`.
3. In `CommandMenu("Playback")`, after the three speed buttons, add a
   `Divider()` then `Toggle("Pause at Each Cue", isOn: $pauseAtEachCue)
   .keyboardShortcut(shortcut(.togglePauseAtEachCue))`.
4. The `@AppStorage("pauseAtEachCue")` stored property is unchanged — same key,
   same binding, only the `Toggle` referencing it relocates.

No other source files change.

## Testing

- **Existing UI tests must stay green.** `PlaybackSpeedUITests`,
  `NewFromTemplateMenuTests`, `ExportSheetScreenshotTests`,
  `OSCMonitorScreenshotTests`, `TimecodeSettingsSheetScreenshotTests`,
  `InspectorClockFramerateUITests` reference menu titles that this change does
  not touch.
- **New UI test (TDD, failing first):** assert the `Cue` menu exists and
  contains an item titled `Duplicate at Playhead`, and that `Pause at Each Cue`
  is reachable under the `Playback` menu. This locks the reorganization in.
- Manual smoke: each moved command still fires its action and respects its
  keyboard shortcut; `Pause at Each Cue` still toggles persisted state.

## Risks

- Low. Surface area is one declarative `Commands` file; no model, command, or
  keymap changes. The only externally observable changes are menu placement and
  six relabeled items, none of which are asserted by existing tests.
