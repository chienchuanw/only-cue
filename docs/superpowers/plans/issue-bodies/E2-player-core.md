## Spec source
Build-sequence step 2 — `docs/build-sequence.md` ("Player core")
Architecture — `docs/architecture.md#layer-responsibilities` (Media layer)

## Done when
`PlayerEngine` plays/pauses/seeks a hardcoded asset. `TransportBar` UI hooked up. `currentTime` updates drive a label.

## Leaves
- [ ] Leaf: `PlayerEngine` (`@Observable`, wraps `AVPlayer`, exposes `currentTime`, `rate`, `status`)
- [ ] Leaf: `PlayerEngine.play() / pause() / seek(to:)` with unit tests
- [ ] Leaf: `TransportBar` SwiftUI view (play/pause button, scrubber, time readout)
- [ ] Leaf: `Time+Format.swift` — `HH:MM:SS.mmm` formatter + tests

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Play and pause
  Given a PlayerEngine loaded with a 30-second audio asset
  When play() is called
  Then rate transitions from 0 to 1
  When pause() is called
  Then rate transitions from 1 to 0

Scenario: Seek
  Given a PlayerEngine loaded with a 30-second audio asset
  When seek(to: 12.5) is called
  Then currentTime is within 0.05s of 12.5

Scenario: Time readout updates
  Given the TransportBar is visible and PlayerEngine is playing
  Then the time readout updates at least once per second
  And the format matches HH:MM:SS.mmm
```

## Out of scope
- Loading user-imported media (E3)
- Video preview pane (E4)
- Waveform (E5)
