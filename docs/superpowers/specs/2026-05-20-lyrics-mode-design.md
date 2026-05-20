# Lyrics Mode — Design

**Date:** 2026-05-20
**Status:** Approved
**New ADR:** ADR-022
**Touches:** `docs/data-model.md` (schema v12 → v13), `docs/architecture.md`

## 1. Goal

Let a lighting designer attach **timestamped lyrics** to a song so they can:

1. **Reference** — see which lyric line is playing while scrubbing the waveform and placing cues.
2. **Run the show** — read a karaoke-style HUD (current line + next) during playback, the way a show caller uses the existing Notes Overlay.

Lyrics are a **per-`MediaItem` annotation layer, fully decoupled from cues** — they are never a cue source and never move cues. This mirrors the tempo map's "visual aid only" philosophy (ADR-020). Cues remain the only first-class timed objects.

## 2. Data model & schema (v12 → v13)

```swift
struct LyricLine: Codable, Identifiable, Equatable {
    var id: UUID
    var time: TimeInterval   // SONG-relative seconds; >= 0
    var text: String         // may be empty → instrumental gap
}

struct Lyrics: Codable, Equatable {
    var lines: [LyricLine]          // normalized: sorted by `time` on construction
    var offsetSeconds: TimeInterval // media playback time where the song begins; default 0

    static let empty = Lyrics(lines: [], offsetSeconds: 0)
}
```

`MediaItem` gains `var lyrics: Lyrics` (default `.empty`), persisted in `.cuelist` alongside `cues` and `tempoMap`.

**Two clocks.** `LyricLine.time` is measured from the start of the *song*. `Lyrics.offsetSeconds` is the media playback time at which the song begins — e.g. an imported file with a one-minute redundant head gets `offsetSeconds = 60`. The two compose into a media-relative time:

```
effectiveTime(line) = line.time + offsetSeconds
```

The offset is a **non-destructive display addend**: `LyricLine.time` values never change when the offset is adjusted, so resetting the offset restores the original sync exactly and the stored timestamps stay pristine. The offset may be large (minutes); it is not a millisecond fine-trim.

**Normalization.** `Lyrics` sorts `lines` by `time` on construction. Empty-`text` lines are legal and meaningful (instrumental gaps). `offsetSeconds` is stored as-is; `effectiveTime` results are clamped to `>= 0` at display sites only.

**Query helpers** (pure, on `Lyrics`):

- `effectiveTime(of:) -> TimeInterval`
- `activeLine(atMediaSeconds:) -> LyricLine?` — the line with the largest `effectiveTime <= playhead`; `nil` before the first line; the last line persists once the playhead is past it (mirrors `MediaItem.activeCue(at:)` semantics).
- `nextLine(afterMediaSeconds:) -> LyricLine?` — the line immediately after the active one; `nil` past the last line.

**Schema.** `lyrics` is a required (non-optional) field, so `ProjectModel.currentSchemaVersion` bumps **12 → 13**. A new `ProjectModel+MigrationV12.swift` migration seeds `lyrics = .empty` on every `MediaItem`; **every** prior migration chain (v1 → current, … v11 → current) also lands `.empty` at the item boundary, exactly as each chain already seeds an empty `tempoMap`. v13 is a one-way upgrade — prior builds cannot open v13 files.

## 3. Commands layer — `OnlyCue/Commands/CueCommands+Lyrics.swift`

All lyric mutation routes through `CueCommands` (the architecture's hard rule — UI never mutates `ProjectModel` directly), giving undo + document-edit tracking for free.

- `setLyrics(_:forItemID:document:undoManager:)` — primitive, whole-`Lyrics` replace, one undo step, no-op when unchanged.
- `setLyricsOffset(_:forItemID:…)` — wrapper; one undo step per committed offset change.
- `setLyricLines(_:forItemID:…)` — wrapper for table edits and tap-along stamps.
- `pasteLyrics(plainText:forItemID:…)` — splits pasted text on newlines into untimed `LyricLine` rows (one row per line, preserving blank lines as empty-`text` rows), replacing the current `lines`.

The Lyrics Editor sheet edits a local working draft and commits via these commands; the implementation plan decides commit granularity (a whole tap-along pass may commit as one `setLyrics` step rather than one-per-tap).

## 4. Authoring — `Tools → Lyrics Editor…` sheet

`LyricsEditorSheet` + `LyricsEditorHost` (a `.lyricsEditorSheet(item:document:)` view modifier on `DocumentView`), following the `TempoMapSheet` / `TempoMapHost` pattern. Opened from a new `Tools → Lyrics Editor…` menu item in `AppCommands`. The sheet is self-contained — `AVPlayer` audio keeps running underneath it, which is all tap-along needs.

**Table.** A `[time | text]` grid. Every cell is directly editable for manual entry and fixups.

**Paste-first.** Pasting (or typing) a whole song's plain text populates the table with **untimed** rows — text present, no timestamp — ready to be timed in one tap-along pass.

**Tap-along.** A highlighted cursor row, the sheet's own minimal play/pause + time readout, and a **Tap** button:

- **Return** (while the sheet owns focus) or the Tap button stamps the cursor row with the **raw current playhead time** (the offset is never baked in here) and advances the cursor to the next row.
- Step-back (a button, plus ⌫) moves the cursor up one row without stamping.
- Re-tapping a row overwrites its time.
- Tapping past the last row is a no-op. Tap-along only *times existing rows* — it never creates rows (rows are added/removed via the table).

Return as the tap key is a **sheet-local behavior**, not a rebindable global shortcut — it does not touch the keymap system.

**Offset control** is also hosted here (see §5), mirrored from the lane header.

## 5. Offset control

The offset is driven by:

- A **typed time field** — accepts `M:SS`, `H:MM:SS`, or `H:MM:SS.mmm`, parsed leniently (a small pure parser, same spirit as the existing timecode-field parsing); the field renders the canonical form on commit.
- A **"Set from playhead"** button — captures the current playhead time as the offset, so the user scrubs to where the song actually starts and clicks once instead of computing a value.

No `±` nudge stepper — the typed field plus set-from-playhead cover both coarse and exact entry. Every offset change commits through `CueCommands.setLyricsOffset` (one undo step).

The control appears in **two places**: the Lyrics Editor sheet, and the **lyric lane header** (§7) — the latter so the user can change the offset while watching the lane slide into alignment with the waveform's vocal transients in real time.

## 6. Playback HUD — `View → Show Lyrics Overlay`

`LyricsOverlayView` — a bottom-center card on `PreviewPane` rendering the **current line bright and the next line dimmed** below it, on the same `.ultraThinMaterial` visual language as the Notes Overlay.

- Toggle: `View → Show Lyrics Overlay`, `@AppStorage`, **default off**, placed next to `Show Notes Overlay`.
- **Independent of the Notes Overlay.** When both are on, the two cards **stack** in a bottom-aligned `VStack` in the overlay layer — Notes card above, Lyrics card below.
- Edge cases: current line has empty `text` → the card renders blank (instrumental gap); playhead before the first line → the card renders nothing; playhead past the last line → the last line persists.
- The HUD resolves the active/next line via `Lyrics.activeLine`/`nextLine` against the engine's `currentTime`.

## 7. Lyric lane — `View → Show Lyrics Lane`

`LyricsLaneView` — a strip in the waveform pane (alongside `CueMarkersOverlay` and `TempoGridOverlay`) showing each line's text positioned by **`effectiveTime`** via `CueMarkersGeometry.position`, so lyrics, cues, and the tempo grid all share one time→x mapping and stay aligned under horizontal zoom.

- Toggle: `View → Show Lyrics Lane`, **per-window session state**, **default off** (matching the tempo grid toggle).
- **Click-to-seek** — clicking a line seeks the playhead to that line's `effectiveTime`, same as clicking a cue marker.
- **Offset feedback** — because lines are positioned by `effectiveTime`, changing the offset slides the whole lane; the lane header hosts the offset control so this is a live, visual calibration loop.
- **Zoom-density collapse** — past a density threshold (too many lines per visible width to render readable text), lines collapse to ticks, the same strategy the tempo grid uses. The lane walks only the visible time window.
- The lane appears in the waveform pane only — not in the Timeline Breakdown view.

## 8. Testing (TDD + BDD)

**Unit:**

- `Lyrics` normalization — `lines` sorted by `time` on construction; empty-`text` rows preserved.
- `effectiveTime`, and `activeLine`/`nextLine` boundary behavior — before first line, on an empty-`text` line, exactly on a line's `effectiveTime`, past the last line.
- Migration v12 → v13 round-trip, and every prior chain (v1 → … v11) lands `.empty` lyrics on every item.
- `setLyrics` / `setLyricsOffset` / `setLyricLines` / `pasteLyrics` — undo/redo, no-op-when-unchanged.
- Plain-text paste parser — newline split, blank-line preservation.
- Offset time-field parser — `M:SS` / `H:MM:SS` / `H:MM:SS.mmm`, rejects garbage.
- Lyric lane layout — time→x positioning and the zoom-density collapse threshold (pure).

**UI (`OnlyCueUITests`, Gherkin acceptance criteria):** open `Tools → Lyrics Editor…` → paste a multi-line block → tap-along stamps a line → close → toggle `Show Lyrics Overlay` and confirm the card → toggle `Show Lyrics Lane` and confirm the strip.

## 9. Out of scope (YAGNI)

- **`.lrc` file import** and **`.lrc` export** — lyrics live only inside the encrypted `.cuelist` in this version.
- **Word-level / karaoke-syllable highlighting** — line-level only.
- **Multiple lyric sets per song** (multi-language / multi-version) — one `Lyrics` per `MediaItem`.
- **Lyric → cue conversion or snapping** — lyrics stay decoupled from cues by design.
- **Lyric lane reordering / multiple lanes.**
- **Rebindable keyboard shortcuts for any lyrics action** — the offset control is on-screen; tap-along's Return is a sheet-local key.

Each of these can be added later without reworking the model, the command seam, or the overlay/lane surfaces.

## 10. Build sequence (for the implementation plan)

Delivered as an **epic of leaf PRs**, each TDD red→green:

1. **Model + migration** — `LyricLine`, `Lyrics` (+ query helpers), `MediaItem.lyrics`, schema v13, `ProjectModel+MigrationV12.swift`, all prior chains seed `.empty`.
2. **Commands** — `CueCommands+Lyrics.swift` (`setLyrics`, `setLyricsOffset`, `setLyricLines`, `pasteLyrics`).
3. **Lyrics Editor sheet — table** — `LyricsEditorSheet` + `LyricsEditorHost`, `Tools → Lyrics Editor…`, paste-first manual table.
4. **Tap-along** — cursor, Return/Tap stamping, step-back, sheet-local transport.
5. **Offset** — typed time field + parser, "Set from playhead", `setLyricsOffset` wiring.
6. **Playback HUD** — `LyricsOverlayView`, `Show Lyrics Overlay`, stacked `VStack` with the Notes Overlay.
7. **Lyric lane** — `LyricsLaneView`, `Show Lyrics Lane`, click-to-seek, offset-driven positioning, zoom-density collapse, offset control in the lane header.
8. **Docs** — ADR-022, `data-model.md` (v13), `architecture.md` (a "Lyrics" section).

## 11. Documentation

- **ADR-022** — "Lyrics are a per-`MediaItem` annotation layer, decoupled from cues; offset is a non-destructive song-start addend." Records the decoupling decision, the two-clock model (song-relative `time` + media-relative `offsetSeconds`), and the deferred items in §9.
- **`docs/data-model.md`** — document `LyricLine` / `Lyrics`, `MediaItem.lyrics`, the v12 → v13 bump and migration, and add `lyrics` to the field-rules table.
- **`docs/architecture.md`** — add a "Lyrics" section mirroring the "Tempo map" / "Notes overlay" sections (the editor sheet, the HUD, the lane, the command seam).
