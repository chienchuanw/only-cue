# Cue-anchored tempo — design

**Date:** 2026-05-13
**Status:** Approved
**Supersedes (in part):** `2026-05-13-ai-tempo-map-design.md` (epic #199 — the per-item `TempoMap` it introduced is replaced by per-cue tempo)
**Depends on:** issue #232 (schema v9 → v10, per-media start timecode) — this work assumes v10 is the baseline and bumps to v11.

## Problem

The current tempo system (epic #199, schema v8) stores a `TempoMap` per `MediaItem`: an ordered list of `TempoSection`s, each with `startSeconds`, `bpm`, `beatsPerBar`, and `downbeatOffsetSeconds`. The grid is edited in `Tools → Tempo Map…`, a standalone sheet whose section table is decoupled from the cue list the designer actually thinks in.

Three pain points:

1. **Two parallel timelines.** Designers reason in cues; the tempo grid is edited in sections. Aligning them is manual and error-prone.
2. **`downbeatOffsetSeconds` is opaque.** It exists because a section's `startSeconds` is rarely where the music's bar 1 lands, so users (or DSP) must nudge the offset until the heavy line lines up with the kick. If a cue could itself *be* the bar 1 anchor, the offset field disappears.
3. **Dead features.** `Tools → Add Cues on Every Beat / Bar` clutters the menu and isn't used.

## Solution

Move tempo onto cues. Each cue may optionally carry `bpm` and `beatsPerBar`; its time becomes bar 1, beat 1 of the segment it opens. The grid is derived at render time by walking BPM-bearing cues in order. The `TempoMap` type, the Tempo Map sheet, and the auto-cue features are removed.

### Data model (schema v10 → v11)

`Cue` gains:

```swift
var bpm: Double?          // 20...400, nil = no tempo change at this cue
var beatsPerBar: Int?     // 1...16, nil = inherit previous (or default 4)
```

Both fields are clamped on decode (out-of-range values are clipped, not rejected, matching `TempoSection`'s current behavior).

`MediaItem` loses `var tempoMap: TempoMap`.

### Derived grid

A new value type `DerivedTempoGrid` (in `OnlyCue/Tempo/`) exposes the surface today's `TempoMap` exposes — `beatTimes(in:)`, `barTimes(in:)`, `nearestBeat(toSeconds:)`, `nearestBar(toSeconds:)` — but is built from the item's cues:

```swift
static func from(cues: [Cue], itemDuration: TimeInterval) -> DerivedTempoGrid
```

Algorithm:

1. Take cues with `bpm != nil`, sorted by time. Each one starts a *segment* that runs until the next BPM-bearing cue's time (or `itemDuration` for the last).
2. Inside a segment opened by cue `C` at time `t` with bpm `b` and beats-per-bar `n` (using the previous segment's `n` when `C.beatsPerBar == nil`, default 4 if none):
   - Beat `j` (j ≥ 0) falls at `t + j × (60/b)`.
   - Beat `j` is a downbeat iff `j % n == 0`. The cue itself is beat 0 — always a downbeat.
3. No segments before the first BPM cue → no grid in that region (consistent with today's "empty map" = no grid).

No `downbeatOffsetSeconds` — the cue's time *is* the anchor.

### Migration v10 → v11

For each `MediaItem` with a non-empty `tempoMap`:

1. For each `TempoSection`, compute `firstDownbeatSeconds = startSeconds + downbeatOffsetSeconds`.
2. Find the cue whose time is closest to `firstDownbeatSeconds` and within one beat (`60 / bpm`) of it.
3. If found: set its `bpm` and `beatsPerBar` to the section's values.
4. If not found: insert a synthetic cue at `firstDownbeatSeconds` named `"Tempo"` carrying the section's `bpm` and `beatsPerBar`. No `cueNumber` (per #229 conventions: new cues are unassigned).
5. Drop the `tempoMap` field from the item's encoded representation.

The migration is **lossy in two ways** — sub-beat downbeat offsets are rounded into the nearest cue, and synthetic cues appear in the cue list where none existed before. Both are bounded and visible to the user; given the recency of #199 and absence of shipped users, this is an acceptable tradeoff for not maintaining two systems.

`MigrationV11` keeps a private decode-only copy of the v10 `TempoMap` / `TempoSection` shape so the live types can be deleted from the app.

### UI

**Cue inspector** gains a "Tempo" group (collapsed unless the cue has BPM set):

- `BPM` numeric field. Placeholder shows the inherited BPM (dimmed) when the cue has none.
- `Beats / bar` stepper (1…16). Defaults to inherited.
- `Detect` button — runs `SpectralFluxTempoAnalyzer` on an audio window starting at the cue's time and ending at the next BPM cue or media end (capped at ~30 s to keep DSP fast). Fills BPM on success; shows "Low confidence (N%)" / "No tempo detected" / "Couldn't open the media file" inline, mirroring `TempoMapSheet`'s current copy.
- `Clear` button — sets both fields to `nil`.

**Cue list pane** gains an optional `BPM` column (off by default, toggleable in the column picker). Reuses #229's `cueNumber` column infrastructure. Blank for cues without BPM, `120` style for those with it.

**Waveform** keeps `View → Show Tempo Grid`. `TempoGridOverlay` is rewritten to consume `DerivedTempoGrid` instead of `TempoMap`. Same line styles for beat vs. downbeat.

**Menus removed** (`OnlyCue/App/AppCommands.swift`):
- `Tools → Tempo Map…`
- `Tools → Split Tempo Section at Playhead` (+ its `KeymapAction.splitTempoSectionAtPlayhead`)
- `Tools → Add Cues on Every Beat`
- `Tools → Add Cues on Every Bar`

**Menus kept:** `View → Show Tempo Grid`, `View → Snap Selected Cues to Nearest Beat`, `View → Snap Selected Cues to Nearest Bar` — these now snap against the derived grid.

### Commands

Delete from `CueCommands+Tempo.swift`: `setTempoMap`, `addTempoSection`, `splitTempoSection`, `removeTempoSection`, `updateTempoSection`, `clearTempoMap`.

Add to `CueCommands+Tempo.swift`: `setCueTempo(cueID:, bpm: Double?, beatsPerBar: Int?, item:, document:, undoManager:)` — single undoable command; passing `nil` to both clears tempo from the cue.

Delete from `CueCommands+Grid.swift`: `addCuesOnEveryBeat`, `addCuesOnEveryBar`.

Modify in `CueCommands+Grid.swift`: `snapSelectedCuesToBeat`/`Bar` take a `DerivedTempoGrid` instead of a `TempoMap`. Call sites build the grid from the active item's cues.

### Tests

**Delete:** `TempoMapTests.swift`, `CueCommandsTempoTests.swift`, `TempoMapSheetScreenshotTests.swift`.

**Add:**
- `DerivedTempoGridTests.swift` — beats/downbeats across a single segment, multi-segment transitions, empty cue list, single-BPM-cue (segment runs to media end), out-of-order cue input (function sorts), `beatsPerBar` inheritance, default fallback when no upstream meter.
- `ProjectModelMigrationV11Tests.swift` — v10 doc with single-section `tempoMap` migrates losslessly when a cue is at `firstDownbeatSeconds`; multi-section map fans out; lossy fallback inserts synthetic "Tempo" cue; empty map drops cleanly; serialization round-trip.
- `CueCommandsSetTempoTests.swift` — set BPM, clear BPM, undo round-trip, no cross-cue mutation, clamping on out-of-range input.

**Keep, retarget:** `CueCommandsGridTests.swift` — same assertions, grid built from cues. `TempoGridOverlayScreenshotTests` — keep file, regenerate fixtures from cue-driven grid.

### Build sequence (leaf PRs)

1. **Schema v10 → v11 + migration.** Add `bpm`/`beatsPerBar` to `Cue`, add `MigrationV11`, drop `tempoMap` from `MediaItem`'s live shape. `MigrationV11` uses its own private decode-only `LegacyTempoMap` / `LegacyTempoSection` structs from day one — the live `TempoMap` / `TempoSection` types are unchanged at this step but already no longer referenced by `MediaItem`. Tests: `ProjectModelMigrationV11Tests`, serialization round-trip.
2. **`DerivedTempoGrid` + consumer swap.** Introduce the new type, switch `TempoGridOverlay` and `CueCommands+Grid` snap commands over. Tests: `DerivedTempoGridTests`. After this PR, the live `TempoMap` type has no remaining consumers (sheet still references it until step 5).
3. **Cue inspector tempo group + Detect.** UI fields + `Detect` button calling `SpectralFluxTempoAnalyzer`. Tests: `CueCommandsSetTempoTests` + inspector snapshot test with/without BPM set.
4. **Cue list BPM column.** Reuses #229's column infra. Pure UI leaf.
5. **Tear down old surfaces.** Delete `TempoMapSheet`, `TempoMapSheet+Fields`, the live `TempoMap` / `TempoSection`, the old `CueCommands+Tempo` impl, `addCuesOnEveryBeat/Bar`, related menu items, `KeymapAction.splitTempoSectionAtPlayhead` and `addCuesOn…` cases. `MigrationV11`'s private `LegacyTempoMap` / `LegacyTempoSection` remain. Tests: delete obsolete suites, app builds, smoke screenshots pass.

Each PR is independently mergeable; ordering is chosen so the grid keeps rendering at every step.

### ADR-020 follow-up

ADR-020 ("tempo is a visual + snap aid, not a cue mover") still holds — but the substrate changes. Add a short note to ADR-020: *"v11: tempo lives on cues; the grid is derived from cue-anchored segments."*

## Out of scope

- Cross-fading between two BPM segments (segment transitions are hard edges).
- Sub-beat resolution (16th-note grid).
- Time-signature display on the waveform.
- Importing tempo from external sources (MIDI, Ableton Link).

## Open questions

None — all design choices were resolved during the brainstorm session.
