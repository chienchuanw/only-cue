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

## Phase 3 — Our differentiator (pick one)

We deliberately defer this until phase 2 ships. Three candidates we've discussed:

### Option A — AI-assisted cueing

Auto-suggest cues from audio analysis: beat grid, transients, vocal entries, instrument changes, scene cuts in video. The user accepts/rejects suggestions; nothing is auto-applied.

**Why it could win**: turns a 4-hour planning session into a 30-minute review session.

**Where it plugs in**: a new `CueSuggester` produces candidate `Cue` values; insertion happens through the existing `CueCommands` API, which means undo and persistence work for free.

### Option B — Real-time collaboration

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
