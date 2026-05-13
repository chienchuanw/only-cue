# Per-Media LTC Timecode & Main-View LTC Strip — Design

> Status: approved 2026-05-13. Source: brainstorm session 2026-05-13. Spec consumed by `writing-plans`.

## Goal

Lift Only Cue's LTC timecode model from a single project-wide start offset to a per-media start timecode, and surface the active media's running timecode (plus a per-clip mute toggle) as a "track" lane in the main view whenever LTC routing is enabled.

The motivating workflow: a show caller pre-rigs media item 1 to start at `01:00:00:00`, media item 2 at `01:15:00:00`, and so on, so that downstream lighting/video consoles synced over LTC see distinct timecode windows per clip. Today the entire project shares one start offset, so adjacent clips collide.

## Scope summary

In scope:

- Per-media `startTimecodeFrames` replacing the project-wide `startOffsetFrames`.
- Schema v9 → v10 migration that fans the old project-wide value out to every existing `MediaItem`.
- Two editing surfaces: an expanded `TimecodeSettingsSheet` with a list of all items, and a per-row context menu on the document sidebar.
- A running-TC ruler lane in the main view, displayed below the waveform only when `LTCRoutingStore.shared.settings.isEnabled`.
- Per-clip LTC mute (`MediaItem.ltcMuted`) toggled from the lane header, undoable via `CueCommands`, persisted with the document.

Out of scope (non-goals):

- Per-media framerate. Framerate stays a single project-wide field on `ProjectTimecodeSettings`.
- Rendering the bi-phase modulated LTC carrier as a waveform. The lane shows TC labels at tick marks, not the audio signal.
- Auto-chaining ("clip 2 starts where clip 1 ended"). Users type explicit start TCs.
- Drop-frame nicety changes — keep whatever `Timecode.parse` already handles.
- LTC strip in the secondary monitor / projector views. Main pane only.

## Data model

### `MediaItem` additions

```swift
struct MediaItem: Codable, Identifiable, Equatable {
    var id: UUID
    var media: MediaReference
    var cues: [Cue]
    var tempoMap: TempoMap = TempoMap()
    var startTimecodeFrames: Int = 0    // NEW — frames since 00:00:00:00 at project framerate
    var ltcMuted: Bool = false          // NEW — persistent per-clip silence of LTC channel
}
```

Both new fields decode as their defaults (`0` / `false`) when missing, so older `.cuelist` payloads still parse.

### `ProjectTimecodeSettings` change

```swift
struct ProjectTimecodeSettings: Codable, Equatable, Sendable {
    var framerate: SMPTEFramerate
    // startOffsetFrames REMOVED in schema v10

    static let `default` = Self(framerate: .fps30)

    /// Map a playback position inside a specific media item to its SMPTE TC,
    /// rounded to the nearest frame. This becomes the single source of truth
    /// for the LTC engine — there is no project-wide start TC anymore.
    func timecode(atPlaybackSeconds seconds: TimeInterval, forItem item: MediaItem) -> Timecode {
        let playbackFrames = Int((seconds * Double(framerate.framesPerSecond)).rounded())
        return Timecode(frameCount: item.startTimecodeFrames + max(0, playbackFrames), rate: framerate)
    }
}
```

The pre-existing `timecode(atPlaybackSeconds:)` overload is removed. Callers (`LTCOutputHost`, the transport-bar TC readout, anywhere else) must pass the active `MediaItem` explicitly.

### Schema v9 → v10 migration

`ProjectModel.currentSchemaVersion` bumps to `10`. The migration in `ProjectModel+MigrationV10.swift`:

1. Read the legacy `timecodeSettings.startOffsetFrames` from the v9 payload (custom decoding container — the field is no longer on the v10 struct).
2. For each `MediaItem`, write `startTimecodeFrames = legacy_offset`. `ltcMuted` initialises to `false`.
3. Re-emit `timecodeSettings` without the offset key.

The migration must be deterministic and lossless: opening a v9 project at default settings (offset = 0) yields every item with `startTimecodeFrames = 0`, byte-identical except for the schema bump. A project with offset = 90 000 (= 01:00:00:00 @ 25fps) ends up with every item at 90 000.

## Editor surfaces

### `TimecodeSettingsSheet` expansion

Existing layout keeps the project framerate picker at the top. Below it, add a new section "Media start timecodes":

```
┌ Timecode Settings ────────────────────────────┐
│ Framerate:  [ 30 fps      ▾ ]                 │
│                                               │
│ ── Media start timecodes ──                   │
│  ▶ preshow.wav           [01:00:00:00] ⓘ      │
│  ▶ act1-stinger.mov      [01:15:00:00] ⓘ      │
│  ▶ intermission.wav      [01:30:00:00] ⓘ      │
│                                               │
│ [ Done ]                                      │
└───────────────────────────────────────────────┘
```

Each row: media icon, file name, a monospaced `HH:MM:SS:FF` text field bound to `startTimecodeFrames` through `Timecode.parse` / `Timecode.description`. Invalid input renders the field's outline red and does not commit; the row's previous value is preserved. The list is reorderable only via the existing sidebar — this sheet is for editing TCs, not reordering.

### Per-row context menu

In the document sidebar's media list, each row gains a context-menu item `Set start timecode…`. Selecting it reveals an inline TC editor pinned to that row (same parser / validation as the sheet field). Confirm commits; ESC reverts.

Both surfaces commit through a new `CueCommands.setStartTimecode(itemID:frames:)` so undo/redo works uniformly.

## Main-view LTC strip

### Placement

The strip is a sibling lane inside the main pane, anchored directly below the waveform area. It is rendered only when `LTCRoutingStore.shared.settings.isEnabled` and a media item is active; otherwise the strip is absent (no empty placeholder).

```
┌────────────────────────────────────────────────────────────┐
│        [waveform + cues + playhead]                        │
├──────┬─────────────────────────────────────────────────────┤
│ 🔉   │ 01:00:00 │ 01:00:05 │ 01:00:10 │ 01:00:15 │  ...    │  ← TC ruler (scrolls)
│ name │  └────────┴──────────┴──────────┴──────────         │
└──────┴─────────────────────────────────────────────────────┘
  ▲                       ▲
  lane header             TC ruler (synced to waveform scroll)
  (fixed, ~120pt wide)
```

Height: 24 pt. Background: a low-contrast fill that visually distinguishes it from the waveform without competing.

### Lane header (fixed)

- Speaker / speaker-slash SF Symbol toggling `ltcMuted` on the active item. Accessibility identifier `ltcMuteToggle.<itemID>` so UI tests can find it.
- Active media file name in a monospaced caption font, truncated with middle ellipsis. Tap on the name is a no-op (the file name is informational; mute is on the icon).

### TC ruler (scrolling)

- Re-uses the `WaveformContainer` scroll position so panning and zooming the waveform pan and zoom the ruler in lockstep.
- Tick generation is a pure helper: given `(durationSeconds, viewportWidth, contentWidthAtZoom, framerate, startTimecodeFrames)`, return an array of `(xPosition, label, isMajor)`. Bucket the tick interval to `1, 5, 15, 30, 60` seconds so labels (~50 pt wide each at the chosen font) never overlap — pick the smallest bucket where `pxPerLabel ≥ 56`. Major ticks every fifth label, slightly taller.
- Labels use `HH:MM:SS` (no frames — too noisy at most zoom levels; the transport readout already shows full `HH:MM:SS:FF` at the playhead).
- Strip is non-interactive for now: clicks pass through to the waveform underneath (so click-to-seek from issue #220 still works when clicking just below the waveform).

### Behavior when no media is active

If `activeItem == nil`, the strip is hidden even when routing is enabled — there is no TC to render. The main-pane empty state is unchanged.

## Per-clip mute behavior

`LTCOutputHost` already manages the LTC `AVAudioEngine`. The mute path:

- `LTCOutputHost` observes `document.model.activeItem?.ltcMuted` via `onChange` (current model already triggers refresh on `timecodeSettings` change; add an analogous `onChange` on the active item's mute flag).
- When `ltcMuted` is true and the engine is running, the LTC-assigned output channel switches its source to silence. Implementation: `LTCAudioOutput` gains a `setLTCMuted(Bool)` API that the host calls. Internally the encoder keeps running so toggling mute is instant — no re-cue glitch.
- Track L / R program-audio channels are unaffected — they continue carrying the routed program audio regardless of `ltcMuted`.
- `LTCOutputHost.refresh(playing:)` is updated so that toggling `ltcMuted` while paused remains a no-op (no engine state change while not playing).

Toggling from the UI:

- Lane-header button calls `CueCommands.setLTCMuted(itemID:muted:)` (new), which mutates the document and emits an undoable operation. Re-toggling within the undo-coalesce window collapses into one undo step.

## CueCommands additions

```swift
extension CueCommands {
    static func setStartTimecode(itemID: UUID, frames: Int) -> CueCommand { ... }
    static func setLTCMuted(itemID: UUID, muted: Bool) -> CueCommand { ... }
}
```

Both follow the existing pattern: read the item, validate (`frames >= 0`), produce a new model + an inverse command for the undo stack.

## Test strategy

### Unit

- `ProjectModelMigrationV10Tests` — round-trip a v9 payload with a non-zero project-wide offset; assert every item in the v10 result has that offset on `startTimecodeFrames`, and that no top-level `startOffsetFrames` key remains. Two cases: offset = 0 (no-op fan-out), offset = 90 000.
- `ProjectTimecodeSettingsTests` — extend to cover `timecode(atPlaybackSeconds:forItem:)`. Cases: item with non-zero start TC + non-zero playback seconds; playback seconds = 0 (returns the item's start); negative seconds clamp to start; rounding at the nearest frame at 29.97 fps.
- `CueCommandsTimecodeTests` — Given/When/Then for `setStartTimecode` (success, negative rejected) and `setLTCMuted` (round-trip, undo restores prior value).
- `LTCTickIntervalTests` (new) — pure helper: given a viewport width and content width at zoom, return the chosen bucket. Cases for each bucket boundary.
- `LTCTickGeneratorTests` (new) — given duration, framerate, start TC, viewport width, content width: assert the generated tick array's labels start at the item's start TC and increment by the chosen bucket.

### UI

- `TimecodeSettingsSheetUITests` — open the sheet, edit the second item's TC to `01:15:00:00`, dismiss, verify the transport readout reads `01:15:00:00` after activating that item with the playhead at 0 s.
- `MainViewLTCStripUITests` — with routing disabled, the strip is absent (`accessibilityIdentifier("ltcStrip")` does not exist). Enable routing in preferences, return to the document, assert the strip appears. Toggle the mute button via `ltcMuteToggle.<itemID>`; assert the SF Symbol's accessibility label flips between `LTC muted` and `LTC unmuted`.
- BDD acceptance from the issue: a Gherkin scenario "Given two media items configured with distinct start TCs, When I activate item 2 and play, Then the transport TC readout shows the second item's TC window" maps to a UI test.

### Pre-flight (per CLAUDE.md and TDD discipline)

Every implementation leaf commits the failing test first, then the implementation. SwiftLint strict-mode rules apply (no single-letter locals, `} else {` same line, etc. — known gotchas from epic #214).

## Implementation leaves (rough sketch — `writing-plans` will detail)

1. **Schema v10 migration + `MediaItem.startTimecodeFrames`** (data only, no UI). The existing transport-bar TC readout and `LTCOutputHost` are routed through the new per-item mapping in this leaf so the codebase stays compilable.
2. **`MediaItem.ltcMuted` + `CueCommands.setLTCMuted` + `LTCAudioOutput.setLTCMuted`** (mute pipeline, no UI yet).
3. **`TimecodeSettingsSheet` expansion** (per-media list with editable TC fields).
4. **Sidebar row context menu** (`Set start timecode…`).
5. **LTC tick helpers** (`LTCTickInterval`, `LTCTickGenerator`) as pure types.
6. **Main-view LTC strip** (lane header + TC ruler, visibility gated on routing).

Each leaf is one PR, one issue, conventional commit, OnlyCue PR template — same shape as epic #214's leaves.

## Risks & open follow-ups

- **Migration risk**: any user who already shipped a v9 project with a meaningful project-wide offset relied on it applying uniformly. The fan-out preserves that behavior bit-for-bit; verify with a screenshot-snapshot regression on the transport TC readout at playback position 0 for a real fixture project.
- **Lane-header width**: the fixed lane header (~120 pt) reduces the waveform's effective viewport width. Verify that the existing waveform zoom/scroll math (`viewportWidth = width - laneHeaderWidth`) still gives sensible playhead positions; if not, the lane header may need to overlay rather than push.
- **`LTCOutputHost` observation overhead**: adding `onChange(of: ltcMuted)` on the active item works only if `activeItem` is observed reactively. If `activeItem` is a computed property that doesn't notify, route the observation through `document.objectWillChange` or hoist `ltcMuted` into a published struct.
- **Undo coalescing for TC edits**: typing into the HH:MM:SS:FF field shouldn't push one undo per keystroke. Coalesce within a 500 ms window per item, same pattern as cue-time edits.
- **Framerate change semantics**: `startTimecodeFrames` is stored at the project framerate. If the user later switches framerate (e.g. 25 → 30 fps), the displayed TC for the same `startTimecodeFrames` *shifts* (90 000 frames is `01:00:00:00` @ 25 fps but `00:50:00:00` @ 30 fps). This matches Reaper's behavior and keeps the data model simple; an explicit "convert TCs to new framerate" command can be a follow-up if users hit it in practice.
