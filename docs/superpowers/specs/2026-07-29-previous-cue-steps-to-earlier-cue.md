# Previous-cue stepping — step to the earlier cue, not the current one

**Status:** approved (2026-07-29)
**Area:** `area:document` — `OnlyCue/Document/MediaItem.swift`

## Problem

Pressing **Previous cue** during playback rewinds to the start of the cue the
playhead is already inside, instead of stepping back to the earlier cue. Found
during hardware verification of MIDI mapping (#699) on a nanoKONTROL2, but the
defect is in shared logic, not in the MIDI layer.

`MediaItem.cue(steppingFrom:direction:)` resolves `.previous` as
"greatest cue time strictly less than the playhead":

```swift
case .previous:
    return candidates.filter { $0.time < currentTime }.max(by: { $0.time < $1.time })
```

Whenever the playhead sits *between* cues — i.e. during normal playback — that
expression selects the currently active cue, not the one before it.

The rule is also self-inconsistent. With cues at 5 / 10 / 15:

| Playhead | Returns | Reads as |
| --- | --- | --- |
| exactly 10 | 5 | steps back correctly |
| 12 | 10 | restarts the current cue |

So the same button means two different things depending on whether the playhead
happens to land exactly on a cue.

## Goal

**Previous = the cue immediately before the active cue**, where active is the
greatest cue with `time <= playhead`. One meaning, independent of where between
cues the playhead sits.

This also makes the pair symmetric: `.next` already means "the cue after the
active one" (from 12 it returns 15, not 10). Only `.previous` is changed.

## Non-goals

- No change to `.next`, `activeCue(at:)`, or `showGoDecision(from:typeID:)`.
- No MIDI-specific step logic. On `dev` the callers are `DocumentView+ShowGo`
  (keyboard + UI) and `OSCServerHost`; the MIDI input host on the unmerged
  `issues/703` branch is a third. All call the same pure function and must keep
  identical semantics — no per-path branching.
- No wrap-around, in either direction.
- No "restart the current cue" affordance is added to replace the removed
  behavior. Anywhere but the first cue, `Prev` then `Next` restores the active
  cue; `Stop` covers back-to-top.

## Behavior

```swift
case .previous:
    guard let active = candidates.filter({ $0.time <= currentTime })
        .max(by: { $0.time < $1.time }) else { return nil }
    return candidates.filter { $0.time < active.time }.max(by: { $0.time < $1.time })
```

Cues at 5 / 10 / 15:

| Playhead | Before | After | Note |
| --- | --- | --- | --- |
| 12 | 10 | **5** | the fix |
| exactly 10 | 5 | 5 | unchanged |
| 7 (inside first cue) | 5 | **nil** | no-op; see below |
| 0 (before any cue) | nil | nil | unchanged |
| 20 (past the last cue) | 15 | **10** | last cue not steppable; see below |

Under a Show-mode type filter (#657) the active cue is resolved **within the
filtered candidate set**, so stepping stays inside one cue type.

### The last cue is not reachable by stepping

Anchoring on the active cue has a corollary worth stating outright: once the
playhead is past the last cue, `.next` is nil (unchanged) and `.previous` now
returns the *second*-to-last, so the last cue cannot be reached from either
side by stepping. A clip with a single cue therefore has an inert Previous
button, and under a type filter that is the ordinary case rather than an edge
one — with typeB cues at 2 and 5, a playhead anywhere past 5 steps to 2.

This is accepted, not overlooked. Direct clicking and `Stop` still reach any
cue, and the alternative — special-casing "past the last cue" to return the
last cue — reintroduces exactly the position-dependent meaning this change
removes.

### First-cue no-op

With the playhead inside the first cue there is no earlier cue, so `.previous`
returns nil and nothing moves. This is symmetric with `.next`, which already
no-ops at the last cue, and back-to-top is already served by the `Stop` action.

Accepted risk: a dead button press gives no feedback and can read as a fault
mid-show. If that proves annoying in practice, this is the decision to revisit
first — not the main rule.

## Test impact

Two existing assertions invert. Both are rewritten, not deleted — each one
pins the old behavior precisely, so the inversion is the proof the change
landed.

- `MediaItemTests.test_cueSteppingPrevious_returnsLastCueStrictlyBeforeCurrentTime`
  — from 12 expected 10, now expects 5. Renamed to describe the new rule.
- `MediaItemTypeFilterTests.test_stepPrev_type_skipsOtherTypes` — the fixture
  (A@1, B@2, A@3, B@5) is unchanged, but the playhead moves from 4 to 6 so the
  type-filtered path keeps a positive stepping case: B candidates are [2, 5],
  active is 5, so it steps to 2. The old playhead-4 case becomes its own test
  asserting nil (active B is 2, nothing earlier).

These keep passing unchanged, which bounds the blast radius:
`test_cueSteppingPrevious_skipsCueAtExactPlayheadTime` (10 → 5),
`test_cueSteppingPrevious_returnsNilWhenPlayheadBeforeFirstCue` (0 → nil),
`test_cueStepping_emptyCues_returnsNilForBothDirections`.

## Acceptance criteria

```gherkin
Scenario: stepping back mid-cue reaches the earlier cue
  Given cues at 5, 10 and 15 and the playhead at 12
  When I step to the previous cue
  Then the playhead seeks to 5

Scenario: stepping back is independent of playhead position within the cue
  Given cues at 5, 10 and 15
  When I step to the previous cue from 10 and from 12
  Then both seek to 5

Scenario: stepping back inside the first cue does nothing
  Given cues at 5, 10 and 15 and the playhead at 7
  When I step to the previous cue
  Then the playhead does not move

Scenario: type-filtered stepping stays within its type
  Given typeA cues at 1 and 3 and typeB cues at 2 and 5
  And the GO type filter is typeB and the playhead is at 6
  When I step to the previous cue
  Then the playhead seeks to 2

Scenario: stepping back past the last cue skips it
  Given cues at 5, 10 and 15 and the playhead at 20
  When I step to the previous cue
  Then the playhead seeks to 10
```

- [ ] `.previous` returns the cue before the active cue.
- [ ] Identical result whether the playhead is exactly on a cue or between cues.
- [ ] nil inside the first cue and before any cue.
- [ ] Past the last cue it steps to the second-to-last (the last cue is not
      steppable), and a single-cue clip always returns nil.
- [ ] Type-filtered stepping resolves the active cue within the filtered set.
- [ ] `.next`, `activeCue(at:)` and `showGoDecision` are untouched.
- [ ] Keyboard, OSC and MIDI all inherit the change (no per-path logic added).
