# Edit Media Modal — Design Spec

Date: 2026-05-17
Status: Approved (brainstorm)

## Problem

The "Edit Media" modal (`OnlyCue/UI/MediaEditSheet.swift`), opened from the Media
Library Sidebar context menu, is a flat SwiftUI `Form` with three controls (Name,
Start timecode, Mute LTC) and no context. The user is editing a clip without
seeing which clip it is — no filename, no kind, no duration, no visual. It looks
generic and gives weak recognition.

## Goal

Two outcomes, selected during brainstorm:

1. **Visual polish & hierarchy** — make the modal feel like a pro tool, not a
   default form.
2. **Add missing context** — surface a file-identity block and a media preview
   (waveform for audio, poster frame for video).

Out of scope: changing the editable fields, timecode-entry redesign, inline
helper text, live name preview, cue-count display. The three editable fields and
their commit flow are unchanged.

## Design

### Layout (Hero preview, stacked)

Fixed-width modal (≈ 460pt), vertical stack:

```
┌─────────────────────────────────────────┐
│  Edit Media                               │  title
├───────────────────────────────────────────┤
│  ▟▆▃ PREVIEW (full-width, ~72pt) ▃▆▟      │  hero strip
├───────────────────────────────────────────┤
│  ♪  opening-theme.wav                      │  identity row
│     Audio · 03:24:11                        │
├───────────────────────────────────────────┤
│      Name  [ Act 1 — Opening            ]  │
│  Start TC  [ 01:00:00:00 ]                  │  Form (unchanged)
│            ( ) Mute LTC for this clip       │
├───────────────────────────────────────────┤
│                      [ Cancel ]  [ Save ]   │  footer (unchanged)
└─────────────────────────────────────────┘
```

- **Hero preview**: full-width, fixed height (~72pt).
  - Audio → reused `WaveformView(peaks:color:verticalZoom:)`.
  - Video → new poster frame (see subsystem below).
  - Loads asynchronously; shows a neutral placeholder while generating.
  - On stale/missing bookmark or generation failure: fall back to a large
    media-kind icon on a muted background. No error text — the identity row
    still names the clip.
- **Identity row**: kind icon + original filename (`item.media.displayName`,
  bold) + secondary line `Kind · SMPTE duration`. Read-only.
- **Form**: the existing three fields with unchanged behavior and unchanged
  accessibility identifiers (`mediaEditNameField`, `mediaEditStartTimecodeField`,
  `mediaEditMuteToggle`, `mediaEditSave`, `mediaEditCancel`).
- **Footer**: Cancel (`.cancelAction`) / Save (`.defaultAction`) — unchanged.

### Video poster-frame subsystem (new)

Mirrors the existing waveform stack for familiarity.

- **`VideoPosterGenerator`**
  - `static func poster(for asset: AVAsset) async throws -> CGImage`
  - `AVAssetImageGenerator`, `appliesPreferredTrackTransform = true`.
  - Capture time = `duration * 0.1`, clamped to ≥ 0 (sub-second clips → ~0).
  - `requestedTimeToleranceBefore` / `requestedTimeToleranceAfter` = `.zero`
    for a deterministic frame.
- **`VideoPosterCache`**
  - Same shape as `WaveformCache.shared`.
  - Key: SHA256(file contents) + target size.
  - Stored as PNG under `~/Library/Caches/OnlyCue/posters/`.
  - `read(...) -> CGImage?` / `write(...)`.
- **`VideoPosterView`**
  - Resolves the security-scoped bookmark off the main actor
    (`Bookmarks.resolve`).
  - Checks cache; on miss, generates then writes cache.
  - Renders the image scaled to fill the hero strip with aspect clipping.
  - Placeholder while loading; fallback icon on failure.
- **`MediaPreviewStrip`**
  - Switches on `item.media.kind`: `.audio` → waveform, `.video` → poster.
  - `MediaEditSheet` embeds this single view.

### Wiring

`MediaEditSheet` gains the data it needs — bookmark data, media kind, duration,
framerate — passed explicitly from `ItemListPane`, **not** the whole
`CueListDocument`, to keep the modal's dependency surface narrow.

No change to `CueCommands.updateMediaItem`, the `MediaItemEdit` DTO, the undo
behavior, `ProjectModel`, `schemaVersion`, or any migration. This is a view +
new cached subsystem change only.

## Testing (TDD)

- **`VideoPosterGeneratorTests`** (unit): capture time equals 10% of duration;
  sub-second clip clamps to ≥ 0; `appliesPreferredTrackTransform` set;
  propagates an error on an undecodable asset. Uses a small bundled fixture.
- **`VideoPosterCacheTests`** (unit): write→read round-trip; key varies by file
  hash and target size; corrupt/missing cache file returns `nil` without
  crashing. Mirrors `WaveformCacheTests`.
- **`MediaPreviewStripTests`** (unit): `.audio` selects waveform path; `.video`
  selects poster path; stale bookmark yields the fallback state.
- **UI** (`MediaEditSheetUITests`): assert the identity filename and a
  `mediaEditPreviewStrip` element exist when the sheet opens; existing
  name-save and cancel tests must still pass (accessibility IDs unchanged).

## Affected files

- Modify: `OnlyCue/UI/MediaEditSheet.swift`, `OnlyCue/UI/ItemListPane.swift`
- New: `OnlyCue/Media/VideoPosterGenerator.swift`,
  `OnlyCue/Media/VideoPosterCache.swift`,
  `OnlyCue/UI/VideoPosterView.swift`, `OnlyCue/UI/MediaPreviewStrip.swift`
- Tests: `OnlyCueTests/VideoPosterGeneratorTests.swift`,
  `OnlyCueTests/VideoPosterCacheTests.swift`,
  `OnlyCueTests/MediaPreviewStripTests.swift`,
  extend `OnlyCueUITests/MediaEditSheetUITests.swift`
- Reused as-is: `WaveformView`, `WaveformCache`, `WaveformGenerator`,
  `Bookmarks`

## Hard-rule compliance

No App Sandbox entitlements, no media embedded in `.cuelist` (bookmark-resolved
only), no `ProjectModel` schema change, macOS deployment target unchanged.
