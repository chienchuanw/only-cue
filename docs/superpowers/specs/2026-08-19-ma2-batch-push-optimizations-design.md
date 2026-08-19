# Send to grandMA2 — batch push & optimizations — design spec

Date: 2026-08-19
Status: approved (grilled with user) — **Figma design signed off 2026-08-19**

## Figma design (signed off)

OnlyCue Design System file `NhH2957iKQ8b581x3gI3Wk`, Screens page:
- Config state — node `612:3180` (song table + per-song slot/executor, duplicate-slot
  red state, auto-number hint, blank-executor, global type-filter chips, preflight
  banner, disabled Push).
- Progress state — node `619:3182` (per-song done / done+auto-numbered / failed-skipped
  / running rows + summary tally + Cancel).

Built from DS tokens/components (Color Dark mode, Button component, Inter/Roboto Mono
text styles). Sheet widened to 640px. Per-song sequence-name input dropped (name is
auto-sanitized from the clip name); type filter rendered as chips.

## Goal

Improve the "Send to grandMA2" flow with four optimizations:

1. Send **multiple songs** in one operation.
2. **Speed up** the live telnet transfer.
3. **Do not force** an executor assignment.
4. **Auto-fill missing cue numbers** so a push always succeeds.

## Background (verified)

Live path is pure telnet (Approach A), one persistent connection, commands sent
one-by-one. Key files under `OnlyCue/MA2/`:

- `MA2PushSheet.swift` — single-item UI entry point (`let item: MediaItem`).
- `MA2PushSheetPresenter.swift:17-19` — resolves one item: `requestedID ?? activeItemID`.
- `MA2PushTarget.swift:57-59` — `isValid` requires `sequenceSlot, timecodeSlot,
  executorPage, executorNumber` all `>= 1` (executor currently mandatory).
- `MA2PushPreflight.swift:18-49` — rejects any nil `cueNumber`; rejects duplicates
  within thousandths.
- `MA2CommandPlanner.swift:64` — always emits `Assign … At Exec page.number`.
- `MA2PushRunner.swift:58,143-149` — fixed `interCommandDelay = 0.3s` **layered on
  top of** the client read time.
- `MA2TelnetClient.swift:25,27,113-127` — `send()` blocks reading the response:
  `firstByteTimeout = 2s` (silent `/nc` commands pay the full 2s), then `settle =
  0.3s` quiet period. No positive "OK" ACK token; only `"Error #"` is structured.
- `CueCommands+MA2.swift:9-28` — `setMA2PushTarget` persists per-clip target after a
  successful push. Live path leaves timecode at MA default ("link selected"); the
  `timecodeSlot` field is effectively vestigial for the live path.

**Timing model:** per-command ≈ read time + `interCommandDelay`. Echoing command
≈ 0.6s; silent command ≈ up to 2.3s. Silent-command timeout is the dominant cost.

## Decisions

### 1. Batch multi-song push (Q1/Q5/Q6/Q7/Q10/Q11)
- New **batch sheet replaces** the single-item sheet. Lists **all songs in the
  project**; user checks which to send.
- Per selected song, two fields: **sequence slot + executor**. `timecodeSlot` is
  **not shown**; internally given a valid value (or relax `isValid` for it).
- **Uniqueness:** sequence slot must be unique across selected songs; executor must
  be unique **when filled** (blank executor skips the check).
- **Defaults:** song with a saved `MA2PushTarget` → reuse it; otherwise auto-increment.
- **Type filter:** one **global** filter applied to all selected songs.
- **Entry points:** right-click a clip → pre-check + scroll to it; menu / active →
  pre-check the active song; all others unchecked; user may add more.
- **Failure handling:** **all-or-nothing preflight** before sending (any invalid
  song blocks the whole batch, flagging which song / which issue). Once sending, a
  per-song telnet error **skips that song and continues**, ending with a
  success/failure summary.

### 2. Faster transfer (Q2/Q9/Q12)
- Target the transfer speed. Two knobs:
  1. `interCommandDelay` 300ms → ~100ms.
  2. Silent-command `firstByteTimeout` 2s → ~0.5s.
- Leave `settle` and per-cue command count alone for now.
- **User has real hardware → aggressive empirical tuning:** step the values down on
  a live console, find the stable floor, then lock the values. Not guessing.

### 3. Optional executor (Q3)
- Executor becomes optional. **Blank → do not emit `Assign … At Exec`**; only Store
  to the sequence pool. Operator assigns later.

### 4. Auto-fill missing cue numbers (Q4/Q8/Q13)
- **Fill only the missing ones**; keep user-entered numbers.
- **Write back to `ProjectModel` via `CueCommands` (undoable)** — not ephemeral.
- Interpolation (cues sorted by timeline):
  - `[1, nil, 3]` → `2`
  - `[1, nil, nil, 4]` → `2, 3`
  - `[1, nil, 2]` (no integer gap) → `1.1`
  - `[nil, nil, nil]` → `1, 2, 3`
  - leading nil → prev number + standard step; no prev → start from 1 (must be
    `< next` and not collide).
  - collisions step to the next unused fractional number (`3` taken → `3.1` → `3.2`).

## Hard rules / constraints

- **UI gate:** any UI change/addition is designed in **Figma first → user sign-off →
  then code**. No UI code before approval.
- Mutations go through the `CueCommands` seam; no direct `ProjectModel` writes.
- Live path stays pure telnet (no FTP/XML).
- Main window dark-only, DS tokens (ADR-024/029). No App Sandbox (ADR-007). No
  embedded media (ADR-006). Deployment target ≥ 14.0 (ADR-001).
- `cueNumber` field already exists on `Cue`; auto-fill likely needs **no schema
  bump** — confirm during implementation, add migration only if a field/semantic
  actually changes.

## Open / to-verify during implementation

- Exact stable floor for `interCommandDelay` / `firstByteTimeout` (measured on the
  user's live console).
- Whether to relax `MA2PushTarget.isValid` for `timecodeSlot` vs. inject a constant.
- Batch preflight aggregation shape (per-song issue list surfaced in the sheet).

## Next steps

1. Figma design for the new batch sheet (song list + per-song slot/executor + global
   type filter + preflight issues + progress/summary) → user sign-off.
2. Implementation plan (`docs/superpowers/plans/`).
3. GitHub issue(s), TDD implementation.
