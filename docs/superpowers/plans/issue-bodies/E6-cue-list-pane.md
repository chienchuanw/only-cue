## Spec source
Build-sequence step 6 — `docs/build-sequence.md` ("Cue list pane")
Data model — `docs/data-model.md` (Cue)

## Done when
Right-side pane shows cues from `ProjectModel.cues`. Empty state when none. Read-only at this stage.

## Leaves
- [ ] Leaf: `CueListPane` view in a `NavigationSplitView` inspector slot
- [ ] Leaf: `CueRowView` — `#`, name, time (formatted), color swatch
- [ ] Leaf: Empty-state view ("No cues yet — press M to add one at the playhead")
- [ ] Leaf: Click-to-seek wiring (selecting a row calls `PlayerEngine.seek(to:)`)

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Empty cue list
  Given a document with no cues
  Then the cue list shows the empty state with the M-key hint

Scenario: List renders cues
  Given a document with 3 cues at times 4.25, 12.0, 18.5
  Then the cue list shows 3 rows in that order
  And each row shows the formatted time HH:MM:SS.mmm
  And each row shows its colorHex as a swatch

Scenario: Click row to seek
  Given a document with 3 cues
  When the user clicks the second row
  Then the player seeks to that cue's time within 50ms
```

## Out of scope
- Adding/editing/deleting cues (E7)
- Drag-to-reorder
- Inline edit
