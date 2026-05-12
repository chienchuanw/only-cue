# Design — Tempo map (Phase 3, option A: AI-assisted cueing)

**Status:** approved (brainstormed 2026-05-13)
**Epic:** to be filed via `/gh-issue` after this spec is reviewed
**Roadmap:** `docs/roadmap.md` — Phase 3, option A ("AI-assisted cueing"), scoped down for v1 to a per-item **tempo map**.
**ADR:** ADR-020 (to be written as the first leaf — summary in §11 below).

---

## 1. Summary

Add a **tempo map** to each media item: an ordered list of *tempo sections*, each carrying a BPM, a bar length, and a downbeat phase. The map is project data, persisted in the `.cuelist` (schema v7 → v8). It renders as a toggleable **beat/bar grid overlay** on the waveform timeline. A pure-Swift DSP analyzer can estimate the BPM and downbeat phase for a section ("Detect tempo"), which the user then corrects by hand. The grid is a **visual and snap aid only** — cues keep absolute-seconds timing; changing a section's BPM moves the grid lines, not the cues. New commands let the user snap selected cues to the nearest beat/bar and bulk-insert cues on every beat/bar in a range.

This is the v1 slice of roadmap option A. The roadmap's broader "auto-suggest cues from audio/video analysis" vision (transients, vocal entries, instrument changes, scene cuts) is explicitly **out of scope** here (§12) — but the analyzer is built behind a protocol so a smarter engine (Core ML, cloud) can replace the DSP one later without touching the UI or the command layer.

## 2. Motivation & context

Phase 2 is feature-complete (LTC, export, templates, custom shortcuts, cue-list editing). Phase 3 is the differentiator; the owner picked options A (AI-assisted cueing) and B (real-time collaboration), to be specced and built **A first, then B**, each as its own epic.

When asked which detectors to ship, the owner reframed option A around a concrete need: *"a feature that allows the user to configure each audio/video to a certain BPM and display the BPM grid. Moreover, the user can split several sections in a media and configure each section with different BPM."* So the centre of gravity for v1 is the **manual tempo-map editor + grid overlay**, with DSP beat-tracking as the thing that seeds it. This is a smaller, lower-risk, fully-additive feature that exercises the "operations through `CueCommands`" idea — useful groundwork before option B.

## 3. Scope

**In scope (v1):**

- `TempoSection` / `TempoMap` value types, persisted per `MediaItem` (schema v8 + migration).
- A pure DSP `SpectralFluxTempoAnalyzer` behind a `TempoAnalyzer` protocol; estimates `{ bpm, downbeatOffsetSeconds, confidence }` for a span of an item's audio.
- A shared `AudioSampleReader` (small refactor extracting the `AVAssetReader → mono Float PCM` glue currently inside `LTCAudioReader`).
- `TempoGridOverlay` on the waveform timeline (beats / downbeats / section boundaries; respects zoom; toggle in the View menu + a `KeymapAction`, default off).
- `TempoMapSheet` (`Tools → Tempo Map…`): table of sections (start, BPM, beats-per-bar, downbeat offset) + Add / Split-at-playhead / Delete + per-section "Detect tempo" + a one-shot "Detect tempo for whole item".
- A quick command "Split tempo section at playhead" (so the common case doesn't need the sheet).
- `CueCommands+Tempo`: `setTempoMap` plus thin add/split/delete/update wrappers, each one undo step.
- Grid snapping: `CueCommands.snapCues(_:toBeatIn:)` / `snapCues(_:toBarIn:)` (reuse the existing batch `snapCues` primitive) wired to new keymap actions; `CueCommands.addCuesOnGrid(in:every:type:)` bulk insert, one undo step.
- Tests (TDD), docs (`architecture.md` §tempo-map, `data-model.md` schema v8, ADR-020, roadmap row).

**Out of scope (v1) — see §12 for the full list:** auto-detection of section boundaries; transient/onset/vocal/instrument/scene-cut cue suggestions; musical-time cue *binding* (cues that re-time when BPM changes); a Core ML / cloud analysis engine; a dedicated video-timeline overlay if video items don't already get a waveform timeline.

## 4. Architecture overview

```
                   ┌───────────────────────────────────────────────┐
                   │ MediaItem.tempoMap : TempoMap                  │  ← persisted (.cuelist v8)
                   │   sections: [TempoSection]                     │
                   └───────────────────────────────────────────────┘
                          ▲                       │ pure queries
        mutations         │                       ▼
   (one undo step each)   │            ┌──────────────────────────┐
 CueCommands+Tempo ───────┘            │ TempoMap helpers:        │
   setTempoMap / add / split /         │  section(atSeconds:)     │
   delete / updateSection              │  beatTimes(in:) /        │
                                       │  barTimes(in:) /         │
 CueCommands (extended):               │  nearestBeat/Bar(to:)    │
   snapCues(_:toBeatIn:/toBarIn:)      └──────────────────────────┘
   addCuesOnGrid(in:every:type:)                  ▲
                                                  │ render
                                       ┌──────────┴──────────┐
                                       │ TempoGridOverlay    │  (waveform pane layer,
                                       │  beats / downbeats  │   like CueMarkersOverlay)
                                       └─────────────────────┘
                                                  ▲
                                       ┌──────────┴──────────┐
                                       │ TempoMapSheet       │  Tools → Tempo Map…
                                       │  (.tempoMapSheet    │  edits sections; "Detect"
                                       │   modifier on       │  buttons call the analyzer
                                       │   DocumentView)     │
                                       └──────────┬──────────┘
                                                  │ analyze(samples:sampleRate:hint:)
                                       ┌──────────▼──────────┐      ┌────────────────────┐
                                       │ TempoAnalyzer       │◀────▶│ AudioSampleReader  │
                                       │  protocol           │      │  (AVAssetReader →  │
                                       │ SpectralFluxTempo-  │      │   mono Float PCM)  │
                                       │  Analyzer (DSP)     │      │  shared w/ LTC     │
                                       └─────────────────────┘      └────────────────────┘
```

New source folder: `OnlyCue/Tempo/` (`TempoSection.swift`, `TempoMap.swift`, `TempoAnalyzer.swift`, `SpectralFluxTempoAnalyzer.swift`, `AudioSampleReader.swift`). New UI files under `OnlyCue/UI/` (`TempoGridOverlay.swift`, `TempoMapSheet.swift`, `TempoMapHost.swift` for the `.tempoMapSheet` modifier). New command file `OnlyCue/Commands/CueCommands+Tempo.swift`. Add `OnlyCue/Tempo/` to `project.yml` sources and re-run `xcodegen generate`.

## 5. Data model

### 5.1 `TempoSection`

```swift
struct TempoSection: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var startSeconds: TimeInterval       // where this section begins on the item timeline
    var bpm: Double                      // clamped to [20, 400] on construction/edit
    var beatsPerBar: Int                 // >= 1 (the time-signature numerator; 4 by default)
    var downbeatOffsetSeconds: TimeInterval  // time from startSeconds to the first downbeat, in [0, barDuration)
}
```

Derived (pure, on the section): `beatDuration = 60 / bpm`; `barDuration = beatDuration * Double(beatsPerBar)`.

Beat grid for a section that spans `[start, end)`: beats at `start + downbeatOffsetSeconds + j * beatDuration` for every integer `j` (positive *and* negative, since `downbeatOffsetSeconds` may exceed one beat), clipped to `[start, end)`. A beat is a **downbeat** when `j` is a multiple of `beatsPerBar`. (So bar 1, beat 1 is at `start + downbeatOffsetSeconds`; a partial bar before it is allowed and drawn.)

Normalization (applied by `TempoMap`, never by the section alone): `bpm` clamped to `[20, 400]`; `beatsPerBar` clamped to `>= 1`; `downbeatOffsetSeconds` reduced modulo `barDuration` into `[0, barDuration)` and clamped `>= 0`.

### 5.2 `TempoMap`

```swift
struct TempoMap: Codable, Equatable, Sendable {
    var sections: [TempoSection]   // invariant: sorted by startSeconds ascending; if non-empty, sections[0].startSeconds == 0; startSeconds strictly increasing
    init()                          // empty == "no grid"
    init(sections: [TempoSection])  // sorts, dedupes by startSeconds (last wins), forces sections[0].startSeconds = 0, normalizes each section
}
```

An **empty** map means "no tempo grid for this item" — the overlay shows nothing, snapping/bulk-insert commands no-op. A non-empty map always covers the whole item from time 0 (the first section is forced to `startSeconds == 0`); the last section runs to the item's end.

Pure query helpers (all bounded — callers pass the range they care about, e.g. the visible waveform window):

- `func section(atSeconds s: TimeInterval) -> TempoSection?` — the section covering `s` (largest `startSeconds <= s`), or `nil` if the map is empty.
- `func sectionEndSeconds(for section: TempoSection, itemDuration: TimeInterval) -> TimeInterval` — the next section's `startSeconds`, or `itemDuration`.
- `func beatTimes(in range: ClosedRange<TimeInterval>, itemDuration: TimeInterval) -> [(time: TimeInterval, isDownbeat: Bool)]` — every beat falling in `range`, tagged downbeat-or-not, walking section by section.
- `func barTimes(in range:itemDuration:) -> [TimeInterval]` — convenience: just the downbeats.
- `func nearestBeat(toSeconds s: TimeInterval, itemDuration: TimeInterval) -> TimeInterval?` / `nearestBar(toSeconds:itemDuration:) -> TimeInterval?` — used by the snap commands; `nil` on empty map.
- `func splitting(atSeconds s: TimeInterval) -> TempoMap` / `func removingSection(_ id: TempoSection.ID) -> TempoMap` / `func updatingSection(_ id:, ...) -> TempoMap` / `func addingSection(atSeconds s:) -> TempoMap` — pure transforms returning a normalized map (used by the command layer). Splitting at `s` clones the covering section's BPM/beatsPerBar and computes the new section's `downbeatOffsetSeconds` so the grid lines are *continuous* across the split (the new section inherits the same beat phase).

### 5.3 `MediaItem` change + schema v8

`MediaItem` gains `var tempoMap: TempoMap = TempoMap()`. Synthesized `Codable` is fine for v8 JSON (encode/decode round-trips the field). The default only matters for *older* JSON, which is handled by the migration, not by `MediaItem` itself.

`ProjectModel.currentSchemaVersion` 7 → **8**. New `migrateFromV7`:

- The v6→v7 migration currently decodes `LegacyV6.items` as `[MediaItem]` (the *current* type) — which breaks once `MediaItem` has a new field, because v6/v7 JSON has no `tempoMap`. So introduce a dedicated snapshot struct `LegacyMediaItemPreV8 { id: UUID; media: MediaReference; cues: [Cue] }` and use it for **both** `LegacyV6.items` and `LegacyV7.items`. (`MediaReference` and `Cue` are unchanged across v6→v8, so they can be reused as-is.)
- `LegacyV7` = the current `ProjectModel` shape minus `tempoMap` on items: `{ schemaVersion, id, name, cuePointTypes, items: [LegacyMediaItemPreV8], activeItemID, timecodeSettings }`.
- `migrateFromV7` maps each `LegacyMediaItemPreV8 → MediaItem(id:, media:, cues:, tempoMap: TempoMap())` and carries `timecodeSettings` through unchanged.
- Update `migrateFromV6` to build `MediaItem(...)` with `tempoMap: TempoMap()` from `LegacyMediaItemPreV8`.
- `test_currentSchemaVersionIsSeven` → `test_currentSchemaVersionIsEight` (assert `== 8`); add round-trip tests: a v7 fixture decodes to a v8 model with every item's `tempoMap` empty; a v8 fixture with a populated tempo map round-trips encode→decode.
- `docs/data-model.md`: document schema v8 and the new field.

## 6. DSP tempo analyzer

### 6.1 Protocol

```swift
struct TempoEstimate: Equatable, Sendable {
    var bpm: Double
    var downbeatOffsetSeconds: TimeInterval   // already reduced into [0, barDuration) for the assumed beatsPerBar
    var confidence: Double                     // 0…1, for surfacing "low confidence" in the UI
}

protocol TempoAnalyzer: Sendable {
    /// Estimate tempo for the given mono PCM. `beatsPerBar` is the assumed time-signature
    /// numerator (so the analyzer can phase-align downbeats). `bpmHint` biases octave-error
    /// resolution toward a plausible range; pass `nil` for the default (≈ 90–160 BPM).
    func analyze(samples: [Float], sampleRate: Double, beatsPerBar: Int, bpmHint: ClosedRange<Double>?) async -> TempoEstimate?
}
```

`nil` means "no detectable periodicity" (silence, ambient drone, speech) — the UI surfaces "no tempo detected" and leaves the section's values alone.

### 6.2 `SpectralFluxTempoAnalyzer` (the v1 implementation)

Pure Swift + Accelerate (`vDSP`, `vDSP_DFT` / `vDSP.FFT`). Pipeline:

1. **Onset envelope.** Downmix to mono (caller already passes mono), short-time FFT (window ≈ 1024–2048 samples, hop ≈ 256–512), magnitude spectrum per frame, half-wave-rectified spectral flux (sum of positive bin-to-bin magnitude increases) → a 1-D onset-strength signal sampled at `sampleRate / hop` Hz. Light smoothing + DC removal.
2. **Tempo estimate.** Autocorrelation (or a comb-filter bank) of the onset envelope over the lag range corresponding to ≈ 40–240 BPM. Pick the dominant peak; resolve octave errors (½×, 2×, ⅓×, 3×) by preferring the candidate inside `bpmHint` (or 90–160 BPM) and the one whose comb response is strongest. Refine to sub-BPM precision by parabolic interpolation around the peak. → `bpm`.
3. **Downbeat phase.** With `beatDuration = 60 / bpm` and `barDuration = beatDuration * beatsPerBar`, slide a bar-length pulse train (impulses at the `beatsPerBar` beat positions, the first weighted highest) over the onset envelope; the offset that maximizes the dot product, taken modulo `barDuration`, is `downbeatOffsetSeconds`. (A cheap, well-understood heuristic — not a learned downbeat detector; "good enough to start, user corrects" per the brainstorm.)
4. **Confidence.** Normalized strength of the chosen autocorrelation peak relative to the envelope energy (and how dominant it was vs. the runner-up). Maps to `[0, 1]`.

This whole chain is **deterministic and pure** given `(samples, sampleRate, beatsPerBar, bpmHint)` → unit-testable without any audio file or hardware.

### 6.3 `AudioSampleReader` refactor

`LTCAudioReader.readMonoSamples(from url:maxSeconds:)` already does exactly the `AVURLAsset → first audio track → AVAssetReaderTrackOutput (LinearPCM, mono, Float32, 48 kHz) → [Float]` work. Extract it into `enum AudioSampleReader { static let sampleRate: Double = 48_000; static func readMonoSamples(from url: URL, range: ClosedRange<TimeInterval>? = nil) async throws -> [Float]; enum Error { case noAudioTrack, readerFailed } }` (add a `range` parameter so the analyzer can pull just a section's span via `AVAssetReader.timeRange`). `LTCAudioReader` keeps its `readMonoSamples` / `decodeTimecodes` API but delegates to `AudioSampleReader` internally — **no behaviour change for LTC**, covered by the existing `LTCAudioReaderTests`. Detection on a video item uses the same reader (its first audio track).

The `Tools → Tempo Map…` "Detect" actions resolve the active item's security-scoped bookmark (via `Bookmarks.resolve`, same pattern as `MediaImporter.stripedTimecode(for:)`), read the relevant span with `AudioSampleReader`, run the analyzer, and write the result into the section through `CueCommands+Tempo`.

## 7. Commands

### 7.1 `CueCommands+Tempo.swift`

`@MainActor extension CueCommands`. Mirrors the `mutateCues` / `setProjectTimecodeSettings` shape — each mutation is **exactly one undo step** with a clear action name, a no-op when the value is unchanged.

- `static func setTempoMap(_ map: TempoMap, item itemID: MediaItem.ID, document:, undoManager:)` — the primitive: snapshot the item's old `tempoMap`, set the new one (normalized via `TempoMap.init(sections:)`), register undo, action name `"Edit Tempo Map"`.
- Thin wrappers built on it: `addTempoSection(atSeconds:item:document:undoManager:)`, `splitTempoSection(atSeconds:item:document:undoManager:)`, `removeTempoSection(_:item:document:undoManager:)`, `updateTempoSection(_ id:bpm:beatsPerBar:downbeatOffsetSeconds:item:document:undoManager:)` (any subset of the last three may be `nil` = leave unchanged). Each just calls `setTempoMap(currentMap.<transform>(...), …)` with its own action name (`"Add Tempo Section"`, `"Split Tempo Section"`, `"Delete Tempo Section"`, `"Change Tempo"`).
- A `clearTempoMap(item:document:undoManager:)` convenience (`setTempoMap(TempoMap(), …)`, action `"Clear Tempo Map"`).

(These operate on whichever item id is passed — usually `document.model.activeItemID` — not implicitly on the active item, so the sheet can be explicit. The `mutateCues`-style "guard `activeItemIndex`" is replaced by "guard the item exists".)

### 7.2 Grid snapping

Extend the existing batch snap, which already takes a `Set<Cue.ID>` and routes through the `snapCues` primitive:

- `static func snapCues(_ ids: Set<Cue.ID>, toBeatIn map: TempoMap, itemDuration: TimeInterval, document:, undoManager:)` — for each selected cue, target = `map.nearestBeat(toSeconds: cue.time, itemDuration:)`; cues whose nearest-beat is the same stay put; one undo step (`"Snap Cues to Beat"`). No-op if the map is empty.
- `static func snapCues(_ ids:, toBarIn map:, itemDuration:, document:, undoManager:)` — same with `nearestBar`, action `"Snap Cues to Bar"`.

Wire to new `KeymapAction`s (editable per epic #40's keymap): e.g. `snapSelectedCuesToBeat`, `snapSelectedCuesToBar` (default chords chosen in leaf 7 — likely modified variants of the existing `S`, e.g. `⇧S` / `⌥S`). The existing plain-`S` snap-to-playhead is untouched.

### 7.3 `addCuesOnGrid`

```swift
enum GridResolution { case beat, bar }
static func addCuesOnGrid(in range: ClosedRange<TimeInterval>, every resolution: GridResolution,
                          type typeID: CuePointType.ID?, document:, undoManager:)
```

Bulk-inserts a cue at every grid position (beats or downbeats) of the active item's tempo map within `range` (default range = the whole item; the UI passes the current selection's span when there's a multi-cue selection, else whole item). New cues get `typeID ?? defaultCuePointTypeID`, fresh UUIDs, names blank, fade times default; cue numbers assigned by the existing `CueNumberAssignment` after merge; one undo step (`"Add Cues on Grid"`). No-op on an empty map or empty range. Guard against pathological counts (e.g. a 20 BPM section over a 2-hour file is fine; but cap at a sane maximum — say 10 000 — and surface a warning rather than locking up).

## 8. UI

### 8.1 `TempoGridOverlay` (waveform layer)

A new `View` placed in `WaveformContainer`'s `ZStack` alongside `WaveformView` / `CueMarkersOverlay` / `WaveformPlayheadLayer`. Because `WaveformContainer.waveformBody` is already at the `function_body_length` cap, add it via a `@ViewBuilder private func tempoGridOverlay() -> some View` helper (same shape as the existing `markersOverlay()`), gated on `showTempoGrid && loadedDuration > 0 && !tempoMap.sections.isEmpty`.

Rendering: thin vertical lines on beats (low opacity), thicker / higher-opacity lines on downbeats, and a slightly distinct marker at each section boundary (a small label `"♩=128"` near the top is a nice-to-have, not required for v1). Uses the same time→x mapping as `CueMarkersOverlay` (`CueMarkersGeometry.position(forTime:width:duration:)`), and only walks `tempoMap.beatTimes(in:)` for the *visible* time window so a zoomed-in 2-hour file doesn't compute a million lines. `.allowsHitTesting(false)` — purely decorative; interaction is via the sheet and the snap commands. Accessibility id `tempoGridOverlay`.

Toggle: a new `View`-menu item "Show Tempo Grid" (checkmark bound to the state) sending a `Notification.Name.toggleTempoGrid`, and a `KeymapAction.toggleTempoGrid` so it's rebindable; the on/off state lives on `DocumentView` (`@State private var showTempoGrid = false`) and is passed down to `PreviewPane → WaveformContainer`. Default **off** (the grid is opt-in, like the timeline breakdown). State is per-window/session, not persisted in the document (consistent with the breakdown / notes overlays).

### 8.2 `TempoMapSheet` (`Tools → Tempo Map…`)

Hosted by a `.tempoMapSheet(item:document:)` `ViewModifier` on `DocumentView` (mirrors `.timecodeSettingsSheet(document:)` / `.exportSheet(...)` host-modifier pattern, so `DocumentView`'s body stays under `type_body_length`). Opened from a `Tools` menu item; disabled when there's no active item.

Contents:

- A header line: the item's display name + duration; a "Detect tempo for whole item" button (replaces the whole map with a single detected section spanning 0…duration).
- A table, one row per `TempoSection` (in `startSeconds` order):
  - **Start** — `MM:SS.mmm`, editable for every section *except the first* (which is pinned at `00:00.000`); editing re-sorts and re-normalizes.
  - **BPM** — a number field + stepper, clamped `[20, 400]`.
  - **Beats / bar** — a small stepper, `>= 1`, default 4.
  - **Downbeat offset** — seconds (or beats) field, shown reduced into `[0, barDuration)`; a "↻ from playhead" affordance sets it so a downbeat lands on the current playhead time (handy: scrub to the first kick, click).
  - **Detect** — runs the analyzer over *this section's* span, fills BPM + downbeat offset, with a per-row spinner while it runs and an inline "no tempo detected" / "low confidence (xx%)" note on completion.
  - **Delete** — removes the section (disabled for the first section when it's the only one; deleting a non-first section merges its span into the previous section).
- A footer: **＋ Add section at playhead** / **Split section at playhead** (the latter clones the covering section's tempo so the grid stays continuous), and a **Clear tempo map** button.

Every edit goes through `CueCommands+Tempo` (so ⌘Z works and the document is marked dirty). The sheet is a thin SwiftUI form over `@ObservedObject document` + the active item's `tempoMap`; the "Detect" actions are `async` tasks that read audio via `AudioSampleReader` and write back via the command layer.

### 8.3 Quick "Split tempo section at playhead" command

A `Tools`-menu item (and `KeymapAction.splitTempoSectionAtPlayhead`) that calls `CueCommands.splitTempoSection(atSeconds: engine.currentTime, item: activeItemID, …)` without opening the sheet — the common live-editing gesture.

## 9. Error handling

- **No active item / item with no audio track** — "Detect" is disabled (no active item) or reports `AudioSampleReader.Error.noAudioTrack` inline ("This item has no audio to analyze"); the tempo map itself is still editable by hand.
- **Bookmark resolution failure** — "Detect" surfaces "Couldn't open the media file" inline; no crash, no partial write.
- **Analyzer returns `nil`** — "No tempo detected" inline; section values unchanged.
- **Empty tempo map** — overlay shows nothing; snap / bulk-insert commands no-op silently; the sheet shows an empty table with the Add/Detect buttons.
- **Pathological grid density** — `addCuesOnGrid` caps the insert count and warns instead of inserting; the overlay always bounds its work to the visible window.
- **Migration of an unknown future schema** — unchanged: `ProjectModel.LoadError.unsupportedSchemaVersion`.
- **Concurrency** — `TempoMap` / `TempoSection` / `TempoEstimate` are `Sendable` value types; `TempoAnalyzer` is `Sendable`; the heavy DSP runs off the main actor (`Task.detached` / an `async` analyzer method) and only the resulting `TempoEstimate` hops back to `@MainActor` to be written through `CueCommands`.

## 10. Testing strategy (TDD throughout — red, then green, commit the failing test when practical)

- **`TempoMapTests`** — normalization invariants (sorted; first section forced to 0; bpm/beatsPerBar/offset clamping; offset reduced mod barDuration); `section(atSeconds:)` across boundaries and before/after the map; `beatTimes(in:)` count + downbeat tagging for 4/4, 3/4, an odd `beatsPerBar`, and a non-zero `downbeatOffsetSeconds` (including offset > one beat → a partial leading bar); `nearestBeat` / `nearestBar` at midpoints and exactly on lines; `splitting(atSeconds:)` keeps the grid continuous; `removingSection` merges spans; multi-section maps with different BPMs.
- **`SpectralFluxTempoAnalyzerTests`** — synthesize a click track at a known BPM and downbeat phase (impulses + a short decaying sine, like the LTC tests synthesize signals) → assert recovered `bpm` within ±0.5 and `downbeatOffsetSeconds` within a small fraction of a beat; an octave-error case (clicks every half-beat → still recovers the musical tempo with the hint); silence / white noise → `nil`; a tempo change handled by analyzing the two halves separately.
- **`AudioSampleReaderTests`** — round-trip a synthesized WAV (written via `AVAudioFile`, as `LTCAudioReaderTests` already does) → mono Float samples; `range:` slicing returns the right span; `noAudioTrack` for a video-less... (covered enough by reusing the LTC fixtures); existing `LTCAudioReaderTests` must still pass unchanged (proves the refactor is behaviour-preserving).
- **`ProjectModelTests`** — `test_currentSchemaVersionIsEight`; v7-fixture → v8 model with empty tempo maps; v8 round-trip with a populated map; the v6 path still works (now via `LegacyMediaItemPreV8`).
- **`CueCommandsTempoTests`** — each of `setTempoMap` / `addTempoSection` / `splitTempoSection` / `removeTempoSection` / `updateTempoSection` / `clearTempoMap` is one undo step that fully reverts; no-op when unchanged; `addCuesOnGrid` inserts the right count at the right times, assigns the default type, is one undo step, and respects the density cap; `snapCues(_:toBeatIn:)` / `toBarIn:` move every selected cue to the nearest grid line in one undo step and no-op on an empty map.
- **UI (committed, not run headless — XCUITests don't launch headless in this repo; the owner runs them in Xcode):** `TempoMapSheetScreenshotTests` (sheet with a couple of sections), and a waveform screenshot test asserting `tempoGridOverlay` exists when the grid is toggled on. Save whatever screenshots the automation can produce into the repo for the owner to eyeball.

## 11. ADR-020 (to be written in leaf 1)

> **ADR-020 — Tempo map is per-item project data and a visual/snap aid, not musical-time cue binding; the analyzer is DSP behind a protocol**
>
> - The tempo map (`TempoMap` of `TempoSection`s) is stored on `MediaItem`, persisted in `.cuelist` (schema v8) — it travels with the project, like `cuePointTypes` and `timecodeSettings`, not as a machine preference.
> - The grid is **decorative + a snap target**. Cues remain timed in absolute seconds; editing a section's BPM moves grid lines, never cues. Musical-time cue binding (cues that re-time with the tempo) is intentionally deferred — it would need a new `Cue` field, a migration, and careful interaction with retime/undo, and the brainstorm chose the simpler model for v1.
> - The v1 detector is a **pure-Swift DSP** spectral-flux/autocorrelation tempo + downbeat-phase estimator (no cloud, no Core ML, no API keys — fits the free, ad-hoc-signed, sandbox-off app and works offline). It sits behind a `TempoAnalyzer` protocol so a Core ML or hosted-API engine can replace it later without touching the UI or `CueCommands`.
> - `AudioSampleReader` is extracted from `LTCAudioReader` as the shared `AVAssetReader → mono Float PCM` reader; LTC behaviour is unchanged.
> - The grid toggle is per-window session state (like the timeline breakdown), not persisted in the document.

## 12. Out of scope (v1) / future work

- **Auto section-boundary detection** — v1 only auto-fills BPM + downbeat phase for a span the user defined; it does not propose *where* to split. A follow-up could add an energy/tempo-change segmenter.
- **The rest of roadmap option A** — transient/onset cues, vocal-entry detection, instrument-change detection, video scene-cut detection. These can each become later leaves (or their own epic) once the tempo-map foundation exists; the `TempoAnalyzer` protocol generalizes naturally to a `CueSuggester` protocol producing candidate `Cue`s.
- **Musical-time cue binding** — see ADR-020.
- **Core ML / cloud analysis engine** — protocol seam is there; not built.
- **Dedicated video-timeline grid** — the overlay lives in the waveform pane; for video items it appears insofar as that pane shows the audio waveform. A separate video scrubber overlay (if/when video gets its own timeline) is a follow-up, not a regression.
- **Per-section time-signature *denominator*** — `beatsPerBar` is the numerator; v1 treats the beat as the displayed pulse and doesn't model 6/8-vs-3/4 distinctions beyond bar length.
- **Tap-tempo / metronome playback** — out of scope; the grid is visual.

## 13. Epic decomposition (issues to file via `/gh-issue`)

One epic ("Tempo map") with these leaves, each independently shippable in a bypass-mode cycle:

1. **Spec + ADR-020 + docs** — this design doc (already written), ADR-020 in `docs/decisions.md`, `docs/architecture.md` §tempo-map skeleton, `docs/roadmap.md` Phase-3 row update.
2. **`TempoSection` / `TempoMap` value types + schema v8 migration** — the types + all pure helpers + `MediaItem.tempoMap` + `migrateFromV7` + `LegacyMediaItemPreV8` + `migrateFromV6` fix + `test_currentSchemaVersionIsEight` + `TempoMapTests` + `ProjectModelTests` updates + `data-model.md`. (No UI, no analyzer.)
3. **`SpectralFluxTempoAnalyzer` + `TempoAnalyzer` protocol + `AudioSampleReader` refactor** — the DSP pipeline + protocol + `TempoEstimate` + extracting `AudioSampleReader` from `LTCAudioReader` (LTC tests stay green) + `SpectralFluxTempoAnalyzerTests` + `AudioSampleReaderTests`.
4. **`CueCommands+Tempo`** — `setTempoMap` + add/split/delete/update/clear wrappers + `CueCommandsTempoTests`.
5. **`TempoGridOverlay` + View-menu toggle + `KeymapAction.toggleTempoGrid`** — the overlay layer in `WaveformContainer`, threaded `DocumentView → PreviewPane → WaveformContainer`; the menu item + notification + keymap action + `DocumentShortcutHints` entry; a waveform screenshot test.
6. **`TempoMapSheet` (`Tools → Tempo Map…`) + "Detect tempo" wiring + quick split command** — the sheet + `.tempoMapSheet` host modifier + the `Tools` menu items + `KeymapAction.splitTempoSectionAtPlayhead` + async detect actions (bookmark resolve → `AudioSampleReader` → analyzer → `CueCommands+Tempo`) + `TempoMapSheetScreenshotTests`.
7. **Grid snapping + `addCuesOnGrid`** — `snapCues(_:toBeatIn:/toBarIn:)` + `addCuesOnGrid(in:every:type:)` + `GridResolution` + new `KeymapAction`s + wiring in `CueListPane` / a `Tools` menu item + tests.

Build order: 2 → 3 → 4 → (5 ‖ 6 once 2–4 land) → 7. Leaves 5 and 6 can overlap; 7 depends on 4 and benefits from 5/6 being in.

## 14. Decided points (no open questions)

- `downbeatOffsetSeconds` is in `[0, barDuration)` (a full-bar phase, not just a beat phase) — lets a section start mid-bar.
- The grid toggle is **off by default** and **not persisted** in the document.
- "Detect tempo" never overwrites without the user clicking it; it fills one section at a time (or the whole item via the explicit button).
- Cues are **not** rebound to musical time (ADR-020).
- v1 detector engine is DSP-only; the protocol seam is the forward-compat story.
