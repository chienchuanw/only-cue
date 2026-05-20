# Editor Mode System — Design

**Date:** 2026-05-20
**Status:** Approved
**New ADR:** ADR-023
**Touches:** `docs/data-model.md` (schema v13 → v14), `docs/architecture.md`
**Supersedes parts of:** `2026-05-20-lyrics-mode-design.md` §4 (the modal Lyrics Editor sheet) and §7 (the `Show Lyrics Lane` toggle)

## 1. Goal

The just-shipped lyrics feature (ADR-022) authors timestamps through a modal sheet: a `[time | text]` table plus playhead tap-along. In practice, **knowing each line's timestamp is tedious** — the timeline is the natural place to see *where* a line belongs, but the sheet hides the waveform while it is open.

This design replaces sheet-based authoring with **direct-on-waveform editing**, and introduces an **editor mode system** so that cue editing, lyric editing, and a read-only performance state never compete for the same clicks.

Three modes, one active at a time, scoped per document window:

1. **Cue mode** — edit cues (today's behavior, formalized).
2. **Lyric mode** — place and retime lyric lines directly on the waveform.
3. **Show mode** — read-only; safe for running the show live.

Lyrics remain a per-`MediaItem` annotation layer, decoupled from cues (ADR-022 is unchanged on that point). This design changes only *how lyrics are authored* and *how the editing surface is gated*.

## 2. The mode system

### 2.1 `EditorMode`

```swift
enum EditorMode: String, CaseIterable, Codable {
    case cue
    case lyric
    case show
}
```

The mode is **per-window working state**, not document data. It is held in `@SceneStorage` so each document window keeps its own mode and restores it across relaunch. The default is `.cue`. The `.cuelist` file format is **not** changed by the mode itself.

`DocumentView` owns the `@SceneStorage` value and threads the current `EditorMode` (and a setter) down to `PreviewPane`, the waveform stack, and the inspector. Menu commands cannot read `@SceneStorage` directly, so the **View ▸ Mode** items and `⌘1/⌘2/⌘3` post an `.editorModeChangeRequested(EditorMode)` notification that `DocumentView` consumes — the same notification pattern the old `Tools → Lyrics Editor…` item used.

### 2.2 Mode switcher

A three-segment `Cue | Lyric | Show` control at the **top of the preview pane**, directly above the waveform. It is always visible — the user must be able to tell the mode at a glance, because the mode changes what clicks do. The active segment carries a mode tint: **blue** (Cue), **purple** (Lyric), **neutral** (Show). OnlyCue has no window toolbar today and this design does not add one.

Also wired: `⌘1` / `⌘2` / `⌘3`, and a **View ▸ Mode** menu group (`Cue Mode`, `Lyric Mode`, `Show Mode`) with those shortcuts and a checkmark on the active mode.

### 2.3 Cross-mode invariant

In **every** mode, a plain click on the waveform body **seeks the playhead**. The mode never hijacks the seek click. Lyric placement (§4) uses a deliberate gesture on the lyric lane, never the waveform-body click. Hold-to-scrub stays available in all modes (it moves the playhead — a transport action, not an edit).

### 2.4 What each mode gates

| Surface | Cue mode | Lyric mode | Show mode |
|---|---|---|---|
| Cue markers | live: select, drag-retime, group-nudge, hotkey-add | visible, **dimmed, locked** | visible, **dimmed, locked** |
| Lyric lane | compact strip, click-to-seek only | **tall editing surface** (§3, §4) | compact strip, click-to-seek only |
| Waveform click | seek | seek | seek |
| Inspector | cue list | lyrics list + unplaced queue (§5) | cue list, read-only (§6) |

**Dimmed + locked** means: rendered at reduced opacity, no hover halo, no drag/select hit-testing. Because a locked marker no longer consumes clicks, clicks fall through to the seek surface — so seek keeps working over a dimmed marker.

## 3. The lyric lane, two sizes

`LyricsLaneView` gains a mode-dependent layout:

- **Lyric mode** — the lane expands to a tall editing strip (~64pt vs today's 26pt) and **always renders full text chips**; the zoom-density tick-collapse is suppressed. The waveform above it stays large — the user places lyrics by reading the waveform's loud/quiet shapes, so the waveform must remain the dominant element.
- **Cue / Show modes** — the lane is the compact 26pt strip with today's tick-collapse behavior (`LyricsLaneLayout`), click-to-seek only.

The lane is shown in Lyric mode unconditionally (empty → it shows a "paste lyrics to begin" affordance). In Cue/Show modes it is shown only when the item has at least one **placed** line (§4) — mirroring today's "lines not empty" condition. The `Show Lyrics Lane` toggle is **removed** (§7); mode now owns lane visibility.

## 4. Lyric authoring on the waveform

### 4.1 Unplaced lines — model change (schema v13 → v14)

A pasted song produces lines with no timestamp yet. Today `LyricLine.time` is non-optional, so "not placed" has no honest representation. It becomes optional:

```swift
struct LyricLine: Codable, Identifiable, Equatable {
    var id: UUID
    var time: TimeInterval?   // SONG-relative seconds, >= 0; nil = UNPLACED
    var text: String          // may be empty → instrumental gap
}
```

`nil` = unplaced (waiting in the queue). A non-nil value = placed, song-relative, `>= 0`. A partly-timed song now persists across save/reopen.

`Lyrics` normalization changes: `lines` is held in **stable authoring order** (paste/song order), no longer sorted on construction. Sorting moves into computed views:

```swift
extension Lyrics {
    var placedLines: [LyricLine]    // time != nil, sorted ascending by time
    var unplacedLines: [LyricLine]  // time == nil, in `lines` (authoring) order
}
```

`effectiveTime(of:)`, `activeLine(atMediaSeconds:)`, and `nextLine(afterMediaSeconds:)` operate on `placedLines` only; `effectiveTime` returns `nil` for an unplaced line. The HUD (`LyricsOverlayView`) and the lane consume `placedLines` — unplaced lines never appear on the timeline.

**Schema.** `ProjectModel.currentSchemaVersion` bumps **13 → 14**, with a new `ProjectModel+MigrationV13.swift` (`migrateFromV13`) registered as `case 13` in the `decode(from:)` dispatch. Every v13 `LyricLine` already carries a concrete `time`, which decodes straight into the optional — so the migration is a no-op on data; only the version label advances. v14 is a one-way upgrade.

### 4.2 The unplaced queue and its cursor

`unplacedLines` is the queue. A **cursor** marks the next-up line, tracked by `LyricLine.ID` (not by index — the list re-sorts as lines are placed; the identity-tracking lesson from the shipped tap-along applies). The cursor is UI working state, not persisted. It defaults to the first unplaced line; placing the cursor line advances it to the next unplaced line; the user can click any line in the inspector queue to make it the cursor. `LyricsTapAlong` is evolved into this queue-cursor type (it already tracks order by `LyricLine.ID`).

### 4.3 Two placement gestures (Lyric mode only)

Both feed the one queue and place the **cursor** line:

- **Tap-along** — during playback the user presses one key per line; the cursor line is placed at the live playhead. Lifted out of the old modal sheet onto the waveform, so lines appear on the lane in real time.
- **Click-to-drop** — the cursor line rides the pointer over the lyric lane as a **ghost chip**; clicking the lane drops it at that time. Works fully paused.

Placement time math (identical for both): a gesture lands at **media time `T`**; the stored value is

```
line.time = max(0, T − offsetSeconds)
```

so `effectiveTime` lands back at `T`. This is the same song-relative convention ADR-022 established; `offsetSeconds` is unchanged.

### 4.4 Correcting placed lines

- **Drag** a placed chip along the lane to retime it — `time = max(0, newMediaTime − offsetSeconds)`. Same gesture vocabulary as dragging a cue marker (`dragThreshold`, live update, commit on release).
- **Right-click** a placed chip → *Send back to unplaced* (`time → nil`, returns to the queue) or *Delete* (removes the line entirely).
- Re-running tap-along / click-to-drop over an already-placed line is reached by first sending it back to unplaced.

## 5. Commands layer

All lyric mutation continues to route through `CueCommands` (the architecture's hard rule). `OnlyCue/Commands/CueCommands+Lyrics.swift` gains:

- `placeLyricLine(id:atMediaTime:forItemID:document:undoManager:)` — sets `time = max(0, mediaTime − offsetSeconds)` for both placement gestures and drag-retime; one undo step.
- `unplaceLyricLine(id:forItemID:…)` — sets `time = nil`.
- `deleteLyricLine(id:forItemID:…)` — removes the line.

Existing commands are kept: `setLyrics` (primitive), `setLyricsOffset`, `setLyricLines` (still used for inspector text edits and reordering), `pasteLyrics` — pasted lines now enter with `time = nil` (unplaced) instead of `time = 0`.

Commit granularity (e.g. a tap-along pass as one undo group vs one-per-tap) is decided by the implementation plan, following the existing tap-along precedent.

## 6. Mode-aware inspector

The right pane swaps content with the mode:

- **Cue mode** — today's `CueListPane`, unchanged.
- **Lyric mode** — a new `LyricsInspectorPane`: a paste box, the **unplaced queue** section (cursor highlighted, click a line to make it the cursor), the **placed lines** list with editable text and a read-only `M:SS.mmm` time, and the offset control (`LyricsOffsetControl`, reused — typed field + "Set from playhead").
- **Show mode** — `CueListPane` rendered **read-only**: its toolbar/edit affordances are disabled and dimmed, and the **current cue is emphasized**. This is the "light performance polish" — no separate front-of-house screen is built.

The inspector swap is a thin container keyed on `EditorMode`; `CueListPane` and `LyricsInspectorPane` stay independent, focused views.

## 7. Removals and migrations of existing UI

- **The modal Lyrics Editor sheet is retired** — delete `LyricsEditorSheet`, its host `ViewModifier`/`View` extension, the `Tools → Lyrics Editor…` menu item, and the `.lyricsEditorRequested` notification. Its capabilities move: table text editing → the Lyric-mode inspector; tap-along → on-waveform placement; offset control → the Lyric-mode inspector.
- **The `Show Lyrics Lane` toggle is removed** — delete the `showLyricsLane` `@AppStorage` key and its `View` menu item. Lane visibility is now mode-driven (§3).
- **Untouched, independent toggles:** `Show Lyrics Overlay` (the HUD), `Tempo Grid`, `Notes Overlay`, `Timeline Breakdown`, `Pause at Each Cue`.
- **Timeline Breakdown stays orthogonal** to modes: it remains a `View`-menu toggle and replaces the waveform when on. Lyric placement requires the waveform lane, so it is simply unavailable while Breakdown is showing; the mode switcher stays visible and the mode still governs the inspector.

## 8. Edge cases

- **No lyrics on the item, Lyric mode** — the tall lane shows a "paste lyrics to begin" affordance; the inspector shows the paste box.
- **All lines unplaced** — nothing renders on the lane (in any mode); the whole queue sits in the inspector.
- **Cursor line deleted / sent back** — the cursor moves to the next unplaced line by identity; if the queue empties, the cursor is `nil` and placement gestures are no-ops.
- **Offset changed mid-authoring** — placed lines slide (they are positioned by `effectiveTime`); stored `time` values are untouched, exactly as ADR-022 specifies.
- **Switching away from Lyric mode mid-placement** — the cursor (working state) is discarded; placed lines persist. Returning to Lyric mode re-seeds the cursor at the first unplaced line.
- **Show mode** — every placement, drag, right-click edit, and hotkey-add is rejected; the mode switcher and transport stay live so the operator can still navigate and exit Show mode.

## 9. Testing (TDD + BDD)

**Unit:**

- `LyricLine.time` optionality — `placedLines` sorted by `time`, `unplacedLines` in authoring order, `effectiveTime` returns `nil` for unplaced.
- `activeLine` / `nextLine` ignore unplaced lines; boundary behavior unchanged from ADR-022.
- Migration **v13 → v14** round-trip; every prior chain (v1 → … v12) still lands correctly and seeds optional `time` values.
- `placeLyricLine` math — `time = max(0, T − offset)`; clamping at `T < offset`; undo/redo; no-op when unchanged.
- `unplaceLyricLine` / `deleteLyricLine` — undo/redo.
- Queue cursor — advances by identity across a re-sort, survives deletion of the cursor line, `nil` when the queue empties.
- `pasteLyrics` — pasted lines enter unplaced (`time == nil`).
- Lane layout — tall vs compact selection by mode; full-chip vs tick-collapse.
- Mode gating (pure where possible) — cue-marker drag rejected outside `.cue`; lyric placement rejected outside `.lyric`; all edits rejected in `.show`.

**UI (`OnlyCueUITests`, Gherkin acceptance criteria):** switch modes via the segmented control and `⌘1/2/3`; in Lyric mode, paste a block → click-to-drop places a line on the lane → drag it → confirm via the inspector; screenshot-smoke for the three-mode layouts (the established pattern for content that is not reliably XCUITest-queryable on CI).

## 10. Out of scope (YAGNI)

- A full front-of-house / performance view — Show mode is lock + light polish only.
- A real macOS window toolbar.
- Modes driving `Show Lyrics Overlay` / `Tempo Grid` / `Notes Overlay` visibility.
- Lyric → cue conversion or snapping (lyrics stay decoupled — ADR-022).
- `.lrc` import/export, word-level karaoke, multiple lyric sets per song (still deferred from ADR-022 §9).
- Multi-select lyric placement; multiple lyric lanes.
- Drag-from-a-tray placement (rejected during design as the most tedious option).

## 11. Build sequence (for the implementation plan)

Delivered as an **epic of leaf PRs**, each TDD red→green:

1. **Model + migration** — `LyricLine.time` optional, `Lyrics` normalization (`placedLines` / `unplacedLines`), `effectiveTime`/`activeLine`/`nextLine` guards, schema v14, `ProjectModel+MigrationV13.swift`.
2. **Commands** — `placeLyricLine`, `unplaceLyricLine`, `deleteLyricLine`; `pasteLyrics` lines enter unplaced.
3. **`EditorMode` + switcher** — the enum, `@SceneStorage` in `DocumentView`, the segmented control in `PreviewPane`, `⌘1/2/3`, the **View ▸ Mode** menu group, the `.editorModeChangeRequested` notification.
4. **Mode-gated interaction** — dim + lock cue markers outside `.cue`; the seek-always invariant; lane dimmed/locked outside `.lyric`.
5. **Tall lane + click-to-drop** — mode-dependent `LyricsLaneView` height, full-chip rendering, the ghost chip, click-to-drop placement, drag-to-retime, the right-click menu.
6. **Tap-along placement** — the queue cursor (evolved `LyricsTapAlong`), key-to-stamp at the playhead in Lyric mode.
7. **Mode-aware inspector** — `LyricsInspectorPane` (paste box, unplaced queue, placed-line text rows, offset control), the inspector swap container.
8. **Show mode polish** — read-only `CueListPane`, dimmed edit chrome, current-cue emphasis.
9. **Cleanup** — retire `LyricsEditorSheet` + host + `Tools` item + `.lyricsEditorRequested`; remove the `showLyricsLane` toggle.
10. **Docs** — ADR-023, `data-model.md` (v14), `architecture.md` (an "Editor modes" section).

## 12. Documentation

- **ADR-023** — "Editing is gated by a per-window editor mode (Cue / Lyric / Show); lyrics are authored directly on the waveform." Records the three-mode model, the seek-always invariant, per-window `@SceneStorage` storage, the `LyricLine.time` optionality and v13 → v14 bump, and the retirement of the modal sheet.
- **`docs/data-model.md`** — document `LyricLine.time` becoming optional (`nil` = unplaced), the `Lyrics` normalization change, and the v13 → v14 bump and migration.
- **`docs/architecture.md`** — add an "Editor modes" section (the `EditorMode` enum, the switcher, mode-gated waveform interaction, the mode-aware inspector); update the "Lyrics" section to point authoring at the waveform instead of the retired sheet.
