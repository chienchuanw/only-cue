# Cue list columns — align to grandMA2 (# · Name · Info) — design

**Date:** 2026-07-18
**Issue:** #661
**Status:** Approved (grilling)

## Goal

Slim the cue-list pane to three grandMA2-style columns — **# · Name · Info** —
dropping the Time and Fade columns. Cue names default to empty (placeholder
only, no "Untitled"), and Info surfaces the existing per-cue notes inline.

## Decisions (locked with the user)

- **Columns:** `# · Name · Info`. Drop **Time** and **Fade** columns.
  - Implication accepted: the list no longer shows each cue's SMPTE time
    (cue markers on the waveform still do); the Time cell was display-only.
- **Info** = the existing `cue.notes`. **Inline-editable** (double-click, like
  the `#` cell). The right-click **Notes sheet** stays. No schema change.
- **Name:** new cues are created with an **empty** name (drop the hard-coded
  `"Cue"`); an empty name renders **blank** when not editing (no "Untitled");
  the edit `TextField` keeps its `"Cue name"` placeholder.
- **Fade:** removed from the UI entirely — no per-cue fade editing anywhere.
  The `Cue.fadeTime` model field stays (created from the cue type's
  `defaultFadeTime`); exports / LTC are unaffected.
- **Width split:** `#` stays a narrow fixed/compressible column; **Name** and
  **Info** are both flexible, Name given the larger share (≈ 6 : 4).

## Architecture

### UI (`OnlyCue/UI/`)

- `CueRowView`: remove the Time and Fade cells; keep `numberCell`; keep
  `nameField` (empty → blank, placeholder preserved); add an inline-editable
  `infoCell` bound to `cue.notes` via a new `onCommitNotes` callback. Row =
  `# | Name | Info`.
- `CueListPane`:
  - `headerRow` → `# · Name · Info` (drop Time/Fade headers + their resize
    handles).
  - `cueRow(for:)` wires `onCommitNotes` → `CueCommands.setNotes(...)`.
- `CueListColumnWidths`: keep the number column; drop the time & fade width
  entries/keys and their resize handles. Name and Info are flexible (no fixed
  width) with Name weighted larger. Recompute `headerMinimumWidth` from the
  number floor + chrome only (lower than today — stays within the #297 budget,
  ≤ inspector min 240).

### Commands (`OnlyCue/Commands/`)

- `CueCommands.appendCue`: `name: "Cue"` → `name: ""`.

### Compatibility

No `ProjectModel` / `.cuelist` schema change. `Cue.fadeTime` and `Cue.notes`
are unchanged; only their UI surfaces move.

## Testing

- **Unit:**
  - New cues are created with an empty name (`CueCommandsTests`).
  - `CueListColumnWidths` / `CueListPaneMinWidthTests`: the min-width floor is
    recomputed without Time/Fade and still ≤ the inspector minimum.
- **UI (XCUITest):** cue rows show `# · Name · Info`; Info edits inline and
  persists; an empty-name cue renders blank (no "Untitled"). Update
  `CueListPaneLayoutUITests` for the new columns; drop Time/Fade assertions.

## Hard-rules check

No schema change, no App Sandbox, no embedded media, macOS 14.0 floor untouched.
No direct `ProjectModel` mutation — Info edits go through `CueCommands.setNotes`.

## Out of scope

Making Time editable; a separate cue inspector; per-cue fade UI (removed).
