# Send to grandMA2 — batch push & optimizations — implementation plan

Spec: `docs/superpowers/specs/2026-08-19-ma2-batch-push-optimizations-design.md` (approved,
Figma signed off).

Four issues, delivered in order **C → B → A → D**. C and B are pure-logic prerequisites
of A's behavior; D needs the user's live console and is last.

Schema: current `currentSchemaVersion = 20`. `Cue.cueNumber: Double?` and
`MediaItem.ma2PushTarget` already persist — **no migration for any of these issues** unless
A changes `MA2PushTarget` field semantics (see A).

---

## Issue C — auto-fill missing cue numbers (feat)

**Goal:** fill only the `nil` `cueNumber`s in a MediaItem, preserving user numbers, writing
back via the CueCommands seam (undoable). Integer-preferring interpolation (user-approved).

**Numbering oracle (approved):**
- `[1, _, 4]` → `1, 2, 3, 4`
- `[1, _, _, 5]` → `1, 2, 3, 4, 5`
- `[1, _, 2]` → `1, 1.1, 2` (no integer gap → +0.1 from lower bound)
- `[_, _, _]` → `1, 2, 3`
- leading `_` with next `5` → fill from `1` upward (`1`, must be `< 5`)
- collision (target integer already used) → step to next unused fractional (`3` taken → `3.1`, `3.2`)

**Files:**
- New `OnlyCue/Commands/CueNumberAutoFill.swift` — pure `enum` function
  `assignments(for cues: [Cue]) -> [Cue.ID: Double]`. Sorts by `time`; walks maximal runs of
  `nil` cues bounded by numbered neighbors; integer-preferring, +0.1 fractional fallback,
  skip-used for collisions. Does NOT reuse `CueNumberAssignment.next` (midpoint semantics —
  rejected by user in favor of integer-preferring).
- New `OnlyCue/Commands/CueCommands+AutoFill.swift` — `autoFillCueNumbers(itemID:document:undoManager:)`
  using `mutateCues(actionName: "Auto-number Cues")`. No-op when no nils. One undo step
  (follows `renumberSelected` pattern in `CueCommands+Renumber.swift`).

**TDD (OnlyCueTests):**
- `CueNumberAutoFillTests.swift` — one test per oracle row + preserves existing numbers +
  empty/all-numbered = no assignments.
- `CueCommandsAutoFillTests.swift` — writes back, undo restores nils, redo re-fills, no-op
  when nothing to fill (follow `CueCommandsTests` helpers: `makeDocumentWithItem`,
  `makeUndoManager` with `groupsByEvent = false`).

---

## Issue B — optional executor (feat)

**Goal:** executor becomes optional. Blank executor → do NOT emit `Assign … At Exec`; only
Store to the sequence pool.

**Files:**
- `OnlyCue/MA2/MA2PushTarget.swift` — make executor optional. Option: `executorPage: Int?`,
  `executorNumber: Int?` (nil = unassigned). `isValid` drops the executor `>= 1` requirement
  (keep `sequenceSlot >= 1`; relax/replace `timecodeSlot` too — see A). **Codable change on a
  persisted struct** → gate behind schema bump + migration (v20→v21) mapping old required
  ints into the optional fields. Confirm during impl whether a bump is truly needed (adding an
  optional may decode old docs fine, but the *meaning* changes — safest to bump).
- `OnlyCue/MA2/MA2CommandPlanner.swift:64` — emit the `Assign … At Exec` line only when both
  executor fields are present.

**TDD:**
- `MA2CommandPlannerTests` — new: executor present → assign line emitted; executor nil → no
  assign line, all other commands unchanged.
- Migration test if bumped (round-trip an old-schema doc).

---

## Issue A — batch multi-song push sheet (feat)

**Goal:** replace the single-item sheet with a batch sheet (Figma `612:3180` / `619:3182`).

**Files:**
- New batch model/view replacing `OnlyCue/UI/MA2PushSheet.swift` (keep `MA2PushSheetPresenter`
  wiring; resolve the *project's items* instead of one). Per-song row = checkbox + name/status
  + `sequenceSlot` + optional executor. Global type-filter chips. Sequence-name input dropped
  (auto-sanitized from clip name, per Figma).
- New `MA2BatchPreflight` — aggregates per-song `MA2PushPreflight` + cross-song uniqueness:
  sequence slot unique across selected; executor unique when present. All-or-nothing: any issue
  blocks the whole batch, surfaced per song.
- Runner orchestration: preflight all → then push each selected song sequentially over the
  telnet path; a per-song telnet error skips that song and continues; end with a
  success/failure summary (Figma progress state).
- Auto-fill hook: on push, run Issue C's `autoFillCueNumbers` for songs with nil numbers
  (write-back, undoable) before building commands.
- Save each song's `MA2PushTarget` (existing `setMA2PushTarget`) after its successful push.

**TDD:**
- `MA2BatchPreflightTests` — duplicate slot across songs blocks; duplicate executor blocks;
  blank executors don't collide; per-song unnumbered surfaces the song.
- Batch runner test (with a fake transport) — continues past a failing song, returns per-song
  outcomes.
- UITests mirror the sheet's accessibility identifiers (checkbox rows, slot/executor fields,
  preflight banner, progress rows).

**Entry points:** right-click a clip → pre-check + scroll to it; menu/active → pre-check active.

## Issue D — faster transfer (perf)

**Goal:** cut per-command latency. Two knobs, made adjustable + empirically tuned on the user's
live console (aggressive real-hardware testing).

**Files:**
- `OnlyCue/MA2/MA2PushRunner.swift:58` — `interCommandDelay` 0.3s → tuned floor (~0.1s), exposed
  as a settable/config value.
- `OnlyCue/MA2/MA2TelnetClient.swift:25` — silent-command `firstByteTimeout` 2s → ~0.5s,
  exposed. Consider a shorter timeout specifically for known-silent `/nc` commands.
- Persist tuned values as settings so the user can adjust at the venue.

**TDD:** timing knobs are injectable; unit-test the config plumbing. Real values are set by
on-console measurement, not asserted in CI.
