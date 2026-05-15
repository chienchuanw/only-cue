# Remove Cue Inspector Pane — Design

**Date:** 2026-05-16
**Status:** Approved (brainstorm)
**Spec section:** Presentation layer. Touches `OnlyCue/UI/CueListPane.swift`, `OnlyCue/UI/CueInspectorView.swift` (deleted), `OnlyCue/UI/InspectorClockHeader.swift` (renamed). Builds on the work in #291 / PR #292 — assumes that PR is merged with a working right-click context menu and the existing Notes / Tempo modal sheets.

## Problem

PR #292 trimmed the Cue Inspector to clock + Number/Name/Fade and moved Type / Notes / Tempo editing into modal sheets reached via right-click. With that landed, the user observed:

> "If there is a modal to edit cue, we don't even need to display cue inspector, or doesn't need to have a cue inspector. And the clock should display above cue list at all time."

The inspector's three remaining fields (Number / Name / Fade) are already editable inline on each cue row via double-click. The clock is the only piece of the inspector that's actively useful at all times — and it doesn't belong inside an inspector, it belongs above the cue list as a persistent playhead readout.

Removing the inspector also lets the cue list pane breathe, and brings the surface closer to the user's reference (CuePoints: clock + cue list on the left, nothing else).

## Decisions

1. **Delete `CueInspectorView` entirely.** The view, its tests, and the empty-state placeholder all go.
2. **Pin the clock above the cue list.** Move the existing `InspectorClockHeader` view to render at the top of `CueListPane`'s content, above the column header row and above the cue rows. The clock stays visible whether the list is populated or empty.
3. **Rename `InspectorClockHeader` → `PlayheadClockHeader`.** The "Inspector" prefix no longer reflects where the view lives.
4. **No new editing surface.** All cue editing keeps the surfaces shipped in #292: inline row edits (Number / Name / Fade double-click), right-click → Change Type ▸ / Edit Notes… / Tempo…
5. **Single-pane left split.** `CueListPane`'s `VSplitView { list ; inspector }` collapses to a single `VStack { clock ; list }`. The horizontal split that contains `CueListPane` is unchanged.
6. **Keep the existing row tint.** No visual change to the row decoration introduced in #292.

## Non-goals

- No new modal. The pivot reuses Notes / Tempo / Change Type from #292.
- No new keyboard shortcuts.
- No new fields on `Cue`, no `.cuelist` schema changes — presentation only.
- No restoration of the inspector for any future "wider window" responsive case. The decision is to delete, not hide.

## Architecture

```
CueListPane
├── PlayheadClockHeader (always visible, pinned at top)
├── (empty state, or)
└── cueList
    ├── headerRow (Time · Number · Name · Fade column titles)
    ├── Divider
    └── scrollableList
        └── CueRowView × N
            ├── stripe (type color)
            ├── Time · Number · Name · Fade
            └── contextMenu { Change Type / Edit Notes… / Tempo… }
                                          │
                              .sheet(item: $activeCueSheet) on body
                              ├── CueNotesSheet
                              └── CueTempoSheet
```

No new components — this is a deletion + a rename + a re-position.

### State / data flow

- The clock view reads `engine.currentTime` (Observation-tracked) and `\.projectFramerate` from the environment — unchanged from PR #292.
- `selectedCue` still exists on `CueListPane` (used by the seek-on-selection logic in `scrollableList`) but is no longer used by any inspector. Keep it private.
- `activeCueSheet` and the sheet routing introduced by the #292 amendment are unchanged.

### Files affected

| File | Change |
|---|---|
| `OnlyCue/UI/CueInspectorView.swift` | **Delete.** The trimmed view ships in #292; this PR removes it. |
| `OnlyCue/UI/InspectorClockHeader.swift` | **Rename** → `PlayheadClockHeader.swift`. Rename the type. Update the `inspectorClock` accessibility identifier → `playheadClock`. |
| `OnlyCue/UI/CueListPane.swift` | Drop the `VSplitView`; render `PlayheadClockHeader` above the existing cue list (or empty state); drop the `private var selectedCue` if no longer used externally. |
| `OnlyCueUITests/InspectorClockHeaderUITests.swift` | Update identifier from `inspectorClock` → `playheadClock`. Rename file → `PlayheadClockHeaderUITests.swift`. Assertions that scope the clock to "inspector empty state" → reframe as "above the cue list". |
| `OnlyCueUITests/InspectorClockFramerateUITests.swift` | Same identifier swap. (This test is already pre-existing-flaky on dev — fix the identifier; the flake is tracked separately.) |
| `OnlyCueUITests/CueInspectorMinimalUITests.swift` | **Delete.** Tested an inspector that no longer exists. The test's assertions (clock present, no removed inspector fields) are subsumed by the layout test below. |
| `OnlyCueUITests/CueListPaneLayoutUITests.swift` | **New.** Asserts `playheadClock` is present and that no `cueInspector` container exists. |
| `OnlyCueTests/CueInspectorMinimalTests.swift` | **Delete.** Asserted Field-enum cases of the deleted view. |

Other tests (`CueRowViewStripeTests`, `CueListColumnWidthsTests`, `CueNotesSheetTests`, `CueTempoSheetTests`, `CueTempoCommitTests`, `CueRowContextMenuUITests`) are unaffected.

## UI specifications

### Cue list pane (new)

```
┌──────────────────────────────────┐
│                                  │
│        01:23:45:18               │  ← PlayheadClockHeader (always visible)
│  ─────────────────────────────── │
│  Time   Cue #   Name      Fade   │  ← existing header row (#291)
│  ─────────────────────────────── │
│  ██ 00:01:23  12  Blackout  3.0  │
│  ██ 00:01:45  13  House up  1.0  │  ← existing rows + right-click menu
│  ██ 00:02:10  14  Standby   —    │
│                                  │
└──────────────────────────────────┘
```

- Clock sits above the column header row with the existing 30pt monospaced SMPTE format.
- When `cues.isEmpty`, the "No cues yet" empty state renders below the clock instead of below the header row. The clock stays visible.
- Pane minimum height: clock minimum (~60pt) + cue list minimum (~120pt) ≈ 180pt — roughly the same as the previous inspector's minHeight.

### Accessibility identifier changes

| Old | New |
|---|---|
| `inspectorClock` (on the SMPTE Text inside `InspectorClockHeader`) | `playheadClock` |
| `cueInspector` (on the inspector pane container) | **removed** |
| `cueInspectorName`, `cueInspectorNumber`, `cueInspectorFade`, `cueInspectorEmptyState`, `cueInspectorNumberError` | **all removed** (with the deleted view) |

### Empty selection

The current inspector empty state ("Select a cue", tertiary text) goes away. The cue list itself handles its own empty state ("No cues yet — Press M to add one at the playhead") — that stays.

## Testing

Following the project's TDD discipline (`CLAUDE.md`):

1. **`CueListPaneLayoutUITests.test_playheadClockIsPresent`** — clock is queryable by its new `playheadClock` identifier and exists when the seed document opens.
2. **`CueListPaneLayoutUITests.test_noInspectorContainer`** — asserts `cueInspector` identifier does **not** exist anywhere.
3. **`CueListPaneLayoutUITests.test_clockSitsAboveCueList`** — fetches the `playheadClock` element and the first `cueRow-*` and asserts `clock.frame.maxY <= row.frame.minY` (within a small tolerance for padding).
4. **`PlayheadClockHeaderUITests`** — renamed from `InspectorClockHeaderUITests`; same SMPTE-format assertions with the new identifier.

All other tests stay green via simple identifier swaps. No new logic to unit-test — this is a structural deletion + relocation.

## Risks / open questions

- **Pane minimum height.** Dropping `inspector minHeight: 180` shrinks the lower bound. The clock + header + a few rows still leaves enough room, but verify on the smallest supported window size (the horizontal split's `frame(minWidth: 240)` is preserved).
- **`selectedCue` is still consumed by `scrollableList`'s `.onChange(of: selection)` to drive seek/scroll**. Confirm the property stays even though no inspector reads it.
- **Pre-existing `testClockRerendersWhenFramerateChanges` flake** (noted on PR #292) lives in `InspectorClockFramerateUITests`. This pivot only renames the file's identifier; it does not attempt to fix the flake. Keep that follow-up issue separate.
- **No regression for inline row editing.** The double-click-to-edit paths for Number / Name / Fade live entirely in `CueRowView` and don't depend on the inspector. Confirmed unchanged.

## Issue scoping

One issue, one PR. Title suggestion: `feat(cue-list): pin playhead clock above cue list; remove cue inspector pane`. Base: `dev`. Depends on PR #292 merging first (so the modal-sheet edit paths exist before the inspector is removed).
