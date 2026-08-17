# Remember a song's LTC (#754)

**Issue:** #754 (`fix: remember song's ltc setting`)
**Date:** 2026-08-17
**Status:** Approved (grill)

## Problem

LTC (linear timecode) in a media file is found by a heuristic audio scan
(`LTCAudioReader.detectTimecodes`) run lazily on display and cached **in memory
only** (`StripedTimecodeCache`, per app run) — nothing is written to `.cuelist`.
The decoder is "tuned for clean signals" and needs ≥2 corroborating frames, so a
file that genuinely carries LTC can scan to `nil` (weak signal, LTC starting
after the 10/60 s window, noise). When that happens the detected badge vanishes,
the SMPTE readout falls back from `FILE` to project settings, and — worst —
**music-only muting stops (`LTCOutputHost` installs no tap), so the LTC tone
bleeds to the audience**. There is no remembered good answer to fall back on.

## Design

Persist a song's detected LTC and fall back to it when a later scan fails.

### Persistence
- New `MediaItem.rememberedLTC: StripedTimecodeTrack?` — the durable "this song
  has LTC" truth. Requires `Codable` on `StripedTimecodeTrack`, `Timecode`,
  `SMPTEFramerate` (all pure value types; synthesizable).
- Schema **v19 → v20** + `ProjectModel+MigrationV20` (structural no-op — new
  optional field, `MediaItem` decodes via `decodeIfPresent`). Update
  `docs/data-model.md` and add an ADR (persisting derived LTC data — a
  deliberate exception to "detected data is never authored").
- **Write policy (write-once):** on the first successful detection where
  `rememberedLTC == nil`, persist the detected track via
  `CueCommands.rememberLTC(_:forItemID:document:)`. Later successful scans do
  **not** overwrite; only an explicit **Re-detect** does. Non-undoable (derived).
- **Relink:** clearing the item's media clears `rememberedLTC`
  (`CueCommands.clearRememberedLTC`) alongside the existing cache invalidate.

### Fallback (centralized)
- `MediaImporter.resolvedStripedTimecode(for:) = (await stripedTimecode(for:)) ?? item.rememberedLTC`.
  Pure part `LTCFallback.resolve(detected:remembered:)` is unit-tested.
- **Every** consumer resolves through this: `StripedTimecodeHost` (env →
  badge/readout/waveform) **and** `LTCOutputHost` (music-only muting) **and**
  `MediaEditSheet`. This is what closes the bleed bug on scan failure.

### The write site
`StripedTimecodeHost` gains the `document`; in its detect task, after a
successful scan with no remembered value, it calls `rememberLTC`. It publishes
`detected ?? item.rememberedLTC`.

## UI (Figma-approved)

- **`MediaEditSheet` — new "LTC" section** (dark sheet `320:2254`): a status line
  (`Detecting…` / `Detected · channel X · TC` / `Remembered · channel X · TC` /
  `Not found`), **Re-detect** (invalidate cache + rescan, overwrites remembered
  on success) and **Clear** (enabled only when remembered exists →
  `clearRememberedLTC`); the existing **Mute LTC for this clip** toggle moves in,
  and a new **Play original source audio** toggle joins it.
- **Item list** (`ItemRowView`): a trailing mono `LTC` micro-label (textSecondary)
  shown when `item.rememberedLTC != nil`. Video/no-LTC rows show none.
- **PreviewPane detected badge**: unchanged text (it renders whenever the resolved
  track is non-nil, so remembered values keep it visible); a tooltip notes when
  the value is remembered vs live.

## Testing
- Codable round-trip: `Timecode`, `StripedTimecodeTrack` (incl. drop-frame rate).
- `MediaItem`: decodes a v19 doc lacking `rememberedLTC` → nil; encode/decode
  round-trip with a value.
- Migration v19→v20 stamps `schemaVersion` and preserves items.
- `CueCommands.rememberLTC` write-once (no overwrite when present); `clearRememberedLTC`.
- `LTCFallback.resolve`: detected wins; nil detected → remembered; both nil → nil.

## Non-goals
- Manual LTC entry (channel/start TC) when never auto-detected — out of scope
  (Q3); the lightweight control point is Re-detect / Clear.
- Slaving playback position to incoming LTC (already out of scope).
