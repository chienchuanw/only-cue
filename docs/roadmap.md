# Roadmap

What comes after the MVP. Nothing here is committed; this document exists so the architecture leaves the right seams open.

## Phase 2 — Pro handoff (closes the gap with CuePoints)

The features that make the app useful **at the desk** during programming, not just at the planning stage.

| Feature | What it adds | Where it plugs in |
|---|---|---|
| **LTC generation** | Generate SMPTE LTC audio that a console chases. Routable to any output device. | New `LTCEncoder` module subscribes to `PlayerEngine.currentTime`. No model changes. |
| **LTC playback** | Play back an existing LTC track from media without regenerating. | Same module, opposite direction. |
| **Templates** | Pre-filled cue lists (e.g. "concert opener", "musical scene break"). | `.cuelist` files with no media; new "New from Template…" menu. |
| **Custom keyboard shortcuts** | User-editable keymap. | `AppCommands` already reads from a JSON keymap; add an editor UI. |
| **Export** | CSV, EDL, Timecode XML, console-specific formats. | Pure transform over `ProjectModel.cues`. |

Phase 2 is **the smallest set of features that makes a working lighting programmer choose us over CuePoints**. We will not ship a paid product without at least LTC + export.

## Phase 3 — Our differentiator

Deferred until phase 2 shipped (it has). Of the three candidates we discussed, **A and B are both in flight** (A first, then B); C remains a future option.

### Option A — AI-assisted cueing — **in progress**

The full vision: auto-suggest cues from audio/video analysis — beat grid, transients, vocal entries, instrument changes, scene cuts. **v1 scope** (epic #199, [`superpowers/specs/2026-05-13-ai-tempo-map-design.md`](superpowers/specs/2026-05-13-ai-tempo-map-design.md), ADR-020): a per-`MediaItem` **tempo map** — configurable per-section BPM + bar length + downbeat phase, a beat/bar grid overlay on the waveform, an on-device DSP "Detect tempo" estimator behind a `TempoAnalyzer` protocol, and snap-cues-to-beat/bar + add-cues-on-grid commands. The grid is a visual + snap aid only; it does not move cues. Transient / vocal-entry / instrument-change / scene-cut suggestion, auto section-boundary detection, a Core ML / cloud engine, and musical-time cue binding are deferred to later leaves.

**Why it could win**: turns a multi-hour planning session into a review session.

**Where it plugs in**: `TempoMap`/`TempoSection` live on `MediaItem` (schema v8); the analyzer reads audio via `AudioSampleReader` (the `AVAssetReader → mono PCM` reader factored out of `LTCAudioReader`); all map edits and cue snapping/insertion go through `CueCommands`, so undo + persistence work for free. The `TempoAnalyzer` protocol generalizes to a `CueSuggester` for the later detectors. See `docs/architecture.md#tempo-map`.

### Option B — Real-time collaboration — **planned (next epic)**

Multiple programmers editing the same cue list live, like Figma. Useful for big shows where lighting + video + sound teams sit in the same session.

**Why it could win**: no other tool in this space has it.

**Where it plugs in**: `CueCommands` becomes the operation log; we add a CRDT or OT layer underneath. The model stays the same; persistence gains a network backend in addition to the local file.

### Option C — Tighter console integration

Direct OSC / MIDI to grandMA3, ETC EOS, Hog 4. Push cues to the console; pull cue numbers back; round-trip programming.

**Why it could win**: removes the manual re-entry step that everyone hates.

**Where it plugs in**: a new `ConsoleBridge` module reads `ProjectModel` and speaks the relevant protocol. Per-console adapters.

## Phase 4 — Platform expansion

Only if phase 2 + 3 succeed.

- **iPad companion** — read-only viewer for the cue list during the show. Same `.cuelist` format over iCloud.
- **Mac App Store** — once we know which integrations require sandbox-incompatible behavior.
- **Windows** — only if a meaningful share of customers ask.

## What we will NOT do (yet)

These come up in conversation; the answer is "no" until something specific changes.

- Multi-track timeline (we are not Pro Tools).
- Lighting rendering / preview (we are not a visualizer).
- Cloud sync as a default (the file is the source of truth).
- A subscription pricing model (one-time or per-major-version, like the reference product).

## Decision log for new features

When a phase-2+ feature is being considered, write an ADR in [`decisions.md`](decisions.md). The bar is:

1. Does it require a `schemaVersion` bump? (most do)
2. Does it route through `CueCommands`? (it should)
3. What seam in `architecture.md` does it use? (must be named)
4. What does removing it cost if it doesn't work? (should be small)
