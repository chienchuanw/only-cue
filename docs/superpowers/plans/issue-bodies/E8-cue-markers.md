## Spec source
Build-sequence step 8 — `docs/build-sequence.md` ("Cue markers on waveform")
Architecture — `docs/architecture.md` (WaveformView)

## Done when
Markers drawn at correct x-positions over the waveform. Drag retimes the cue. Click seeks the player.

## Leaves
- [ ] Leaf: `WaveformView` overlay layer drawing one marker per cue
- [ ] Leaf: Marker hit-testing for click/drag
- [ ] Leaf: Drag gesture mutates time via `CueCommands.retime` (single undo step per drag)
- [ ] Leaf: Click on marker calls `PlayerEngine.seek(to: cue.time)`
- [ ] Leaf: Marker color reflects `cue.colorHex`
- [ ] Leaf: Snap-to-frame behavior is OFF for v1 (free-form retime)

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Markers render
  Given a document with 3 cues at 4.25, 12.0, 18.5 and a 30s waveform
  Then 3 markers appear at the corresponding x-positions
  And each marker uses its cue's color

Scenario: Drag retimes
  Given a marker at 12.0s
  When the user drags it +50px (= +5s on the current zoom)
  Then the cue's time is approximately 17.0
  And ⌘Z restores 12.0 in a single undo step

Scenario: Click seeks
  Given a marker at 18.5
  When the user clicks the marker
  Then the player seeks to 18.5 within 50ms
```

## Out of scope
- Hover preview / tooltip (E9 polish)
- Keyboard nudge ("←" / "→" to retime)
- Snap to grid
