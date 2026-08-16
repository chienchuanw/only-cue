# Batch Change Cue Type (multi-select) — design spec

Date: 2026-08-16
Status: approved (grilled with user)

## Goal

In `CueListPane`, when multiple cues are selected, let the user change the
**type** of every selected cue at once via the existing right-click "Change
Type" menu — and fix the currently-invisible ✓ (selected-type checkmark) in
that menu as a side effect of the rendering change.

## Background (verified)

- Selection is already multi-select: `CueListPane.swift:72`
  `@Binding var selection: Set<Cue.ID>`.
- The existing `Menu("Change Type")` (`CueListPane+Sheets.swift:129-151`) only
  ever acts on the single row under the cursor, and shows the current-type ✓ via
  a `Label { … } icon:` slot — which **native macOS `NSMenu` does not render**,
  so no checkmark is ever visible.
- `CueCommands.setType(cueId:to:…)` mutates only `typeID`. Batch precedent:
  `renumberSelected` / `nudgeCues` (take `Set<Cue.ID>`, one `mutateCues` call =
  one undo step).
- Fade still exists (`Cue.fadeTime`); this feature does not touch it.
  `CuePointType.defaultFadeTime` is a dead field — out of scope.

## Decisions

1. **(Q1)** Upgrade the existing "Change Type" menu in place: acts on the whole
   selection when `selection.count >= 2`; single-cue behavior unchanged when
   one is selected.
2. **(Q2)** Cursor-priority targeting: if the right-clicked row is **in** the
   selection → act on the whole `selection`; if **not** → act on that row only.
   Targets = `selection.contains(cue.id) ? selection : [cue.id]`.
3. **(Q3)** Unified-checkmark rule: show the ✓ on a type only when **all**
   targets share that type; any divergence → no ✓.
4. **(Q4/Q5)** Render with an inline `Picker` (`.pickerStyle(.inline)`), one
   `.tag(type.id)` per type (mirrors `ShowGoTypePicker.swift:19-26`). The
   binding getter returns the unified `typeID` or a sentinel (divergence);
   setter calls the batch command. Single- and multi-select share one code path,
   so the single-cue checkmark is fixed alongside.
5. **(Q6)** Mutate only `typeID`; leave `fadeTime` / name untouched, consistent
   with `setType`.

## Implementation (within the command seam)

- New command `CueCommands.setTypeForSelected(_:to:document:undoManager:)` in a
  new `OnlyCue/Commands/CueCommands+Type.swift`. Empty set = no-op. One
  `mutateCues` call, `actionName: "Change Cue Type"` (one undo step).
- `CueListPane+Sheets.swift`: replace the `ForEach`-of-`Button` inside
  `Menu("Change Type")` with an inline `Picker` bound to a computed binding:
  - get: `Set(targets.map(\.typeID)).count == 1 ? thatTypeID : sentinel`
  - set: `CueCommands.setTypeForSelected(targetIDs, to:newTypeID, …)`
  - Keep accessibility identifiers `cueRowContextChangeType` /
    `cueRowContextChangeType-<type.id>`.

## Acceptance (TDD — red first)

- Unit (primary):
  1. `test_setTypeForSelected_changesAllSelected`
  2. `test_setTypeForSelected_isOneUndoStep`
  3. `test_setTypeForSelected_preservesFadeAndOtherFields`
  4. `test_setTypeForSelected_emptySelection_isNoOp`
- UITest: select 2 rows → right-click → change type → both rows' type column
  updates (the ✓ itself is not XCUITest-assertable).

## Explicitly out of scope

- Applying a type's default fade / name pattern on type change.
- Fixing `deleteSelected()`'s N-step-undo debt.
- Removing the dead `defaultFadeTime` field (needs schema bump + migration).
- Any schema change (no model change here).
