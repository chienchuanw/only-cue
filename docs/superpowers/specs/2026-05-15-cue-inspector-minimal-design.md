# Cue Inspector Minimal Redesign — Design

**Date:** 2026-05-15
**Status:** Approved (brainstorm)
**Spec section:** Presentation layer; touches `OnlyCue/UI/CueInspectorView.swift`, `OnlyCue/UI/CueListPane.swift`, `OnlyCue/UI/CueRowView.swift`. Consumes `ProjectModel.colorHex(for:)`, `CueCommands.setType / setNotes / setBPM / setBeatsPerBar`, existing tempo-detect plumbing.

## Problem

The Cue Inspector pane currently presents seven distinct sections — clock, type picker, number, name, fade, notes, and tempo (BPM + beats-per-bar + Detect/Clear with status). Flat visual hierarchy means every field competes equally. Notes is cramped at a 60pt minimum height despite being the most-edited freeform field. The tempo block is heavy (two fields + two buttons + status text) yet only used on cues with musical content. Type, set once per cue, occupies a top-level row.

Power users programming a show repeatedly edit Name, Number, and Fade. Notes, Type, and Tempo are set-once / occasional. The inspector should match that frequency curve.

Separately, the cue list row shows the cue's type only via a faint full-row background tint (`listRowBackground`). The signal is weak, and there is no Fade column at all — Fade is only editable in the inspector.

## Decisions

1. **Inspector becomes minimal.** Only Clock + Number + Name + Fade remain inline. Type, Notes, and Tempo move out.
2. **Right-click is the new entry point** for Type, Notes, and Tempo on a selected cue.
    - Change Type → submenu (instant commit, no sheet).
    - Edit Notes → modal sheet, ⌘⌥N.
    - Tempo → modal sheet, ⌘⌥T.
3. **Sheets are explicit-commit.** Cancel (Esc) discards; Save (⌘⏎) commits via the existing `CueCommands` calls. No autosave-on-type inside the sheet (unlike inline fields).
4. **Cue list row gains a left color stripe** (~3pt, full row height) in the cue's resolved type color. The existing faint full-row tint (`listRowBackground`) is **kept** as additional reinforcement.
5. **Cue list row gains a Fade column** between Name and the right edge, resizable like Time and Number.
6. **Column order left → right:** stripe · Time · Number · Name · Fade.
7. **Inspector has no top stripe.** With every list row carrying its own visible stripe immediately adjacent to the inspector, an inspector-side stripe would duplicate the signal.
8. **Double-click on a cue row** keeps its current meaning (inline name rename). It is *not* overloaded to open the Notes sheet — right-click is the single discovery path for the new modals.
9. **Number column stays blank when `cueNumber == nil`** — current behavior preserved.

## Non-goals

- No changes to `.cuelist` schema. Layout-only.
- No new fields on `Cue` or `ProjectModel`.
- No keyboard shortcut for opening the inspector or changing focus across panes.
- No popover variant of the sheets — they are always modal sheets attached to the document window.
- No removal of "Manage Types…" — it appears at the bottom of the Change Type submenu, mirroring the existing Tools-menu action.
- No change to tempo-detect logic; the Detect button + status string move verbatim into the Tempo sheet.

## Architecture

```
DocumentView
├── CueListPane (right of split)
│   └── List
│       └── CueRowView                 ← gains left stripe + Fade column
│           ├── stripe (RoundedRectangle, type color, 3pt wide)
│           ├── Time
│           ├── Number
│           ├── Name
│           └── Fade                    ← new column, double-click to edit inline (mirrors number)
│       .contextMenu                    ← gains 3 new entries
│           ├── Change Type ▸ (existing types + Manage Types…)
│           ├── Edit Notes…   ⌘⌥N
│           └── Tempo…        ⌘⌥T
│
└── CueInspectorView (left of split)
    ├── InspectorClockHeader            ← unchanged
    ├── Number (TextField)
    ├── Name   (TextField)
    └── Fade   (TextField)
                                         ← Type / Notes / Tempo removed

Sheets (presented from DocumentView via .sheet bindings):
├── CueNotesSheet      ← new view; large TextEditor; Save commits via CueCommands.setNotes
└── CueTempoSheet      ← new view; BPM + beats-per-bar + Detect + Clear; Save commits via existing CueCommands
```

### State / data flow

- **Stripe color:** `document.model.colorHex(for: cue)` → `Color(hex:)`. Falls back to `Color.clear` when nil (same logic as `CueListPane.rowTint`).
- **Type submenu:** built from `document.model.cuePointTypes`. Selecting an item calls `CueCommands.setType(cueId:to:document:undoManager:)`. Current type gets `Image(systemName: "checkmark")` accessory.
- **Notes sheet** holds its own `@State var draft: String` initialized from `cue.notes`. Save → `CueCommands.setNotes`. Cancel → drop draft. Re-opening always re-initializes from current model state (no persistent draft across opens).
- **Tempo sheet** holds `@State` for `bpmDraft`, `beatsPerBarDraft`, plus the existing `detectingCueID` / `detectMessage` analogue scoped to the sheet's lifetime. Detect runs against the cue's media just like today; result populates the BPM draft but does *not* auto-save — user still must press Save. Clear sets both drafts to empty. Save commits both via `CueCommands.setBPM` and `CueCommands.setBeatsPerBar` atomically (sequential calls inside one undo group).
- **Sheet activation source of truth:** DocumentView owns two `@State var` bindings — `notesSheetCueID: Cue.ID?` and `tempoSheetCueID: Cue.ID?`. The context menu sets them; the `.sheet(item:)` API drives presentation. Closing the sheet (Cancel or Save) sets the binding back to nil.

### Files affected

| File | Change |
|---|---|
| `OnlyCue/UI/CueInspectorView.swift` | Remove `typePicker`, `tempoSection`, Notes `TextEditor`, related drafts and `Field` cases. ~247 → ~110 lines. |
| `OnlyCue/UI/CueInspectorView+Tempo.swift` | Delete or fold into `CueTempoSheet.swift`. |
| `OnlyCue/UI/CueRowView.swift` | Add leading color stripe, add Fade column with double-click inline edit (mirror existing Number cell pattern). |
| `OnlyCue/UI/CueListPane.swift` | Wire `Fade` column width into `CueListColumnWidths` and the resizable column logic; add new context-menu entries; present sheets from here or pass binding up to `DocumentView`. |
| `OnlyCue/UI/CueListColumnWidths.swift` | Add `fadeDefault` constant. |
| `OnlyCue/UI/CueNotesSheet.swift` | **New.** Modal sheet view. |
| `OnlyCue/UI/CueTempoSheet.swift` | **New.** Modal sheet view; absorbs tempo-detect helpers from `CueInspectorView+Tempo.swift`. |
| `OnlyCue/UI/DocumentView.swift` | Owns `notesSheetCueID` / `tempoSheetCueID` state and `.sheet(item:)` modifiers; declares ⌘⌥N / ⌘⌥T keyboard shortcuts via `.keyboardShortcut` on the menu items (or via a hidden `CommandGroup`). |

## UI specifications

### Inspector pane

```
┌──────────────────────────────────────┐
│                                      │
│           01:23:45:18                │  ← clock (existing InspectorClockHeader)
│  ──────────────────────────────────  │
│   Number   [ 12              ]       │
│   Name     [ Blackout        ]       │
│   Fade     [ 3.0             ]       │
│                                      │
└──────────────────────────────────────┘
```

- 60pt caption-style label column, rounded-border text fields. Commit-on-blur and commit-on-submit unchanged.
- Empty state ("Select a cue") unchanged.
- No background tint, no top stripe.

### Cue list row

```
┌──┬──────────┬─────┬──────────────────┬───────┐
│██│ 00:01:23 │ 12  │ Blackout         │ 3.0   │
└──┴──────────┴─────┴──────────────────┴───────┘
 stripe  Time   Num    Name              Fade
```

- Stripe: `RoundedRectangle(cornerRadius: 1)`, 3pt wide, fills full row height including the row's vertical padding. Color = cue's resolved type color; `.clear` when unresolved.
- Faint row tint (`.listRowBackground(rowTint(for: cue))`) is preserved.
- Fade column: double-click to edit inline (same pattern as the Number cell, using `FadeTime.parse` / `format`). Commits via `CueCommands.setFadeTime`.

### Right-click context menu (new entries appended to existing)

```
…
─────────────────────────────
Change Type            ▸    → submenu: ● Type A ✓
                                      ● Type B
                                      …
                                      ─────────
                                      Manage Types…
Edit Notes…           ⌘⌥N
Tempo…                ⌘⌥T
```

### Notes sheet

- Title: `Notes — Cue {number} · {name}` (number omitted if nil).
- `TextEditor` filling the sheet, min 280×180.
- Footer: `Cancel` (Esc) on the left of Save; `Save` (⌘⏎) is default.
- No autosave; closing without Save discards.

### Tempo sheet

- Title: `Tempo — Cue {number} · {name}`.
- Fields: BPM (placeholder "inherited"), Beats per bar (placeholder "4").
- Action row: `Detect` (with progress + status text), `Clear` (resets both drafts).
- Footer: `Cancel` (Esc) / `Save` (⌘⏎). Save commits both fields under a single undo group.

## Testing

Following the project's TDD discipline (`CLAUDE.md`):

1. **Inspector unit tests** — confirm only Number/Name/Fade fields render; no Picker, no TextEditor for notes, no BPM/beatsPerBar fields. Existing focus / commit / draft-sync tests for the three remaining fields stay green.
2. **CueRowView unit tests** — stripe renders with the resolved type color; stripe hides (`Color.clear`) when type unresolved; Fade column renders, double-click enters edit mode, commit calls `CueCommands.setFadeTime`.
3. **Sheet unit tests** —
    - Notes sheet: Save commits via `CueCommands.setNotes`; Cancel does not; re-opening reflects current model.
    - Tempo sheet: Save commits BPM and beatsPerBar via the right commands; Detect populates draft but does not commit; Clear resets drafts; Cancel after Detect leaves model untouched.
4. **Context menu UI test** — right-click a cue row, verify the three new menu items exist with their shortcuts; selecting Change Type → a type commits via `CueCommands.setType`; selecting Edit Notes / Tempo opens the corresponding sheet.
5. **Keyboard shortcut UI test** — with a cue selected, `⌘⌥N` opens the Notes sheet; `⌘⌥T` opens the Tempo sheet.
6. **Regression** — existing inspector tests for Name/Number/Fade/clock continue to pass with no edits to their assertions other than removing references to removed fields.

All UI tests use `UITestSeedHandler` per the existing pattern from #263.

## Risks / open questions

- **Sheet lifetime when selection changes.** If a sheet is open for cue A and the user clicks cue B in the list, should the sheet stay (acting on A) or dismiss? Decision: **stay** — the sheet is bound to a specific cue ID, not to the current selection. Same model as a popover anchored to a row.
- **Tempo detect cancellation.** Today, navigating away from a cue mid-detect cancels the in-flight detect (via `detectingCueID` check). Moving Detect into the sheet means the sheet owns the in-flight task; closing the sheet must cancel it. Wire to `.onDisappear`.
- **Undo grouping in Tempo sheet.** Save commits BPM and beats-per-bar separately under the same `undoManager`. Verify with a unit test that one undo step reverses both.
- **Accessibility identifiers** — the new sheets and Fade column need stable identifiers (`cueNotesSheet`, `cueNotesSheetSave`, `cueTempoSheet`, `cueTempoSheetBPM`, etc.) for UI tests. Listed in the test plan above.
