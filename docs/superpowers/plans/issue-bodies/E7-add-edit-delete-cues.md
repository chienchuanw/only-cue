## Spec source
Build-sequence step 7 — `docs/build-sequence.md` ("Add / edit / delete cues")
Architecture — `docs/architecture.md#layer-responsibilities` (Commands layer rule: UI never mutates ProjectModel directly)

## Done when
`M` key adds at playhead. Inline rename, color picker, time edit, delete. All routed through `CueCommands` with `UndoManager`.

## Leaves
- [ ] Leaf: `CueCommands.addCueAtPlayhead(player:document:)` with undo registration
- [ ] Leaf: `CueCommands.delete(cueId:document:)` with undo
- [ ] Leaf: `CueCommands.rename(cueId:to:document:)` with undo
- [ ] Leaf: `CueCommands.recolor(cueId:to:document:)` with undo
- [ ] Leaf: `CueCommands.retime(cueId:to:document:)` with undo
- [ ] Leaf: `M` keyboard shortcut bound in `AppCommands`
- [ ] Leaf: Inline rename on row double-click
- [ ] Leaf: Color picker popover from row swatch
- [ ] Leaf: Delete via row swipe action and `⌫` key
- [ ] Leaf: `CueCommandsTests` covers each command's add + undo + redo path

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Drop a cue at the playhead
  Given a document with sample.mp3 loaded
  And the playhead is at 00:00:12.500
  When the user presses M
  Then a new cue appears in the cue list at index 0
  And the cue time equals 12.500 seconds
  And the action is undoable

Scenario: Undo restores prior state
  Given the previous scenario completed
  When the user presses ⌘Z
  Then the cue list is empty

Scenario: Rename
  Given a cue at index 0
  When the user double-clicks the name and types "Chorus"
  Then the cue's name is "Chorus"
  And ⌘Z restores the prior name

Scenario: Delete
  Given a cue at index 0
  When the user presses ⌫
  Then the cue is removed
  And ⌘Z restores it with the same id and time
```

## Out of scope
- Cue markers on waveform (E8)
- Drag-to-reorder
- Multi-select operations
