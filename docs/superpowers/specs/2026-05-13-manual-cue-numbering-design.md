# Manual cue numbering with grandMA2 ordering — design

**Status:** approved (brainstorm 2026-05-13)
**Spec section implemented:** TBD link in the OnlyCue verification footer of the implementing PR(s); for now, this file is the spec.

## Problem

Today, creating a cue (a "marker") auto-assigns a `cueNumber` via `CueNumberAssignment.next`, which fits the new cue between its time-neighbors with a fractional value. Users have no chance to opt out, and the auto-assigned numbers drift away from grandMA2 conventions as cues are inserted, deleted, and reordered.

We want manual numbering with grandMA2 ordering rules, while keeping today's playback and OSC/MA behavior intact.

## Goals

- Creating a cue (any path that the user perceives as "drop a marker") leaves `cueNumber` unassigned.
- The user types cue numbers explicitly in the cue list and inspector.
- Cue numbers, when set, follow grandMA2 format and ordering rules.
- Unnumbered cues remain fully functional — they play locally and through OSC/MA bridges; they just have no number label.

## Non-goals

- Changing playback semantics for numbered or unnumbered cues.
- Changing how `CueCommands+Grid.swift` (every-beat / every-bar) numbers cues — the grid action is the user explicitly asking for a numbered sequence and stays as-is.
- Changing the cue-list sort order (still by `time`).
- Reworking the OSC/MA protocol. We will document what happens for unnumbered cues but not redesign downstream messaging.

## Rules (grandMA2)

A valid cue number, when set:

1. **Format:** `0.001 ≤ n ≤ 9999.999`, with at most 3 decimal places.
2. **Unique** within the active item's cue list.
3. **Strictly ascending by time** against the cue's immediate numbered time-neighbors. Let `prev` be the numbered cue with the greatest `time < self.time`, and `next` the numbered cue with the smallest `time > self.time` (unnumbered cues are skipped when picking neighbors). Require `prev.cueNumber < n < next.cueNumber`. If a neighbor is absent the corresponding bound is open.

`nil` (unassigned) is always allowed and clears the cell.

The strict-ascending rule is enforced **only at the moment of explicit number assignment**, against current time-neighbors. Retime / nudge / snap / duplicate never modify `cueNumber`; if a retime reorders cues so that existing numbers are no longer ascending in time, the numbers persist. The next time the user edits a number, the rule is enforced fresh against the new neighbor positions.

## Data model

`Cue.cueNumber` becomes `Double?` (was `Double`). `nil` ≡ unassigned.

Schema bumps from v8 to **v9**:

- `Cue` now encodes `cueNumber: Double?`. Swift's synthesized `Codable` writes `null` for `nil` and decodes a missing key to `nil`.
- `currentSchemaVersion = 9` in `ProjectModel.swift`.
- `ProjectModel+Migration.swift` gets a `LegacyV8` struct mirroring today's `ProjectModel` shape with a `LegacyV8Cue { cueNumber: Double }`. `migrateFromV8` lifts each old cue's `Double` into the new `Double?` — every pre-v9 cue keeps the number it already had. No "clear-on-migrate."
- The `case 8:` arm is added to the existing decode switch alongside the v1–v7 cases. The previously-current `case currentSchemaVersion:` path now decodes v9 directly.

## Command layer (`OnlyCue/Commands/CueCommands.swift`)

- `appendCue` (used by both `addCueAtPlayhead` overloads): set `cueNumber: nil`. Remove the call to `CueNumberAssignment.next`.
- `duplicateAtPlayhead`: set `cueNumber: nil` on the new cue. Copies type / name / notes / fade as today.
- `setCueNumber(cueId:, to newNumber: Double?, …)`: signature widens to `Double?`. Validation runs before mutating; the command returns:

  ```swift
  enum CueNumberValidation: Equatable {
      case ok
      case invalidFormat
      case duplicate
      case outOfRange(lowerExclusive: Double?, upperExclusive: Double?)
  }
  ```

  Validator algorithm:
  1. `nil` → `.ok`, mutate (clears the number).
  2. Not in `0.001 ... 9999.999` or more than 3 decimal places (test: `(n * 1000).rounded() == n * 1000`) → `.invalidFormat`.
  3. Any *other* cue in the active item has the same number → `.duplicate`. (A cue committing its own current number to itself is `.ok`.)
  4. Compute `prev` / `next` numbered time-neighbors of the cue being edited (unnumbered cues skipped). Require `prev?.cueNumber < n` and `n < next?.cueNumber` (open bounds; `nil` neighbor → that side is unbounded). Otherwise `.outOfRange(lower, upper)`.

- Retime / `nudgeCues` / `snapCues`: untouched. `cueNumber` persists through time changes.

`OnlyCue/Commands/CueNumberAssignment.swift`: no longer called from `CueCommands.swift`. `CueCommands+Grid.swift` still needs sequential numbering for the every-beat / every-bar grid action; that file currently constructs cues with explicit sequential numbers, so the existing helper either shrinks to a `nextSequential(in: cues)` form or is inlined into the grid command. The cleanup is decided in the plan, not here.

## UI

`OnlyCue/UI/CueInspectorView.swift` + `CueInspectorCommit.swift` (number field):

- Empty when `cue.cueNumber == nil`; otherwise `FadeTime.formatNumber(n)`.
- Empty submission → `setCueNumber(…, to: nil, …)`.
- Non-empty submission → parse, call `setCueNumber(…, to: parsed, …)`, branch on the returned validation case:
  - `.ok` → field shows the canonical-formatted committed value.
  - `.invalidFormat` → field reverts to the prior value; inline label: "Use 0.001–9999.999, up to 3 decimals."
  - `.duplicate` → reverts; "Already in use."
  - `.outOfRange(lower, upper)` → reverts; "Must be between {lower} and {upper}." Half-open variants: "Must be less than {upper}." / "Must be greater than {lower}." Bounds formatted via `FadeTime.formatNumber`.
- Error label clears on the next keystroke or successful commit.

`OnlyCue/UI/CueListPane.swift` (cue-number column):

- Blank cell when `cue.cueNumber == nil`. No placeholder dash or hint.
- Inline edit reuses the same commit path. If the cell can't host a sub-row error, fall back to a transient tooltip on the cell. Decided during implementation.

`OnlyCue/UI/PreviewPane.swift`:

- `cueNumberLabel: activeCue.flatMap { $0.cueNumber.map(FadeTime.formatNumber) }`. The downstream `NotesOverlayView` already takes `String?` and hides the prefix when `nil`.

`OnlyCue/UI/CueMarkersOverlay.swift`:

- When `cue.cueNumber == nil`, omit the number label from the marker badge. The marker still renders.

## Migration & testing

**Migration (`OnlyCueTests`):**

- v8→v9 round-trip: fixture v8 JSON with cues numbered `1.0`, `1.5`, `2.0` decodes to v9 with `cueNumber == .some(1.0 / 1.5 / 2.0)`.
- Existing v1–v7 migration chain tests stay green.

**Validator (unit tests on `CueCommands.setCueNumber`'s returned `CueNumberValidation`, or on an extracted helper if the chain is awkward to drive through the command in tests):**

- Empty list → any well-formed number accepted.
- Format edges: `0.0009` rejected; `0.001` accepted; `9999.999` accepted; `10000` rejected; `1.0001` rejected (4 decimals); `1.5` accepted.
- Uniqueness: rejects equal number; accepts the cue editing its own number to itself.
- Strict-ascending: cues at `t1 < t2 < t3` numbered `1, 2, 3` — editing `t2` to `1.5` ok, `2.5` ok, `0.5` rejected, `3.5` rejected.
- Unnumbered neighbors skipped: cues at `t1 < t2 < t3 < t4` with numbers `1, nil, nil, 2` — editing `t2` or `t3` requires `n` in `(1, 2)`.
- Half-open boundaries: editing the earliest-in-time cue with no earlier numbered cue → only upper bound applies. Editing the latest → only lower bound applies.

**Command layer:**

- `addCueAtPlayhead` produces `cueNumber == nil`.
- `duplicateAtPlayhead` produces `cueNumber == nil`.
- `retime` / `nudgeCues` / `snapCues` preserve `cueNumber`, including when the resulting ordering inverts numbering.
- `setCueNumber(to: nil)` clears the number and is always accepted.
- Undo of `setCueNumber` restores the prior value (including `nil`).

**UI (light — where they pull weight):**

- `CueInspectorView` shows an empty field for `nil`, surfaces the error label on invalid commit, reverts the field on rejection.
- `CueListPane` row renders a blank cell for `nil`.

## Out of scope / explicit non-changes

- Playback / OSC / MA: unnumbered cues still play and trigger normally. The OSC/MA bridge's behavior for unnumbered cues will be confirmed when writing the implementation plan (grep the bridge path); if a real protocol question surfaces, the plan flags it rather than silently inventing a format.
- Cue-list sort order: still by `time`.
- `CueCommands+Grid.swift`: unchanged.
