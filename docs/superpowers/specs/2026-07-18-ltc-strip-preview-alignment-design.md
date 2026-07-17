# LTC strip ↔ preview playhead alignment — design

**Date:** 2026-07-18
**Issue:** #663
**Status:** Approved (grilling)

## Goal

Make the LTC strip's ruler line up horizontally with the waveform/preview
above it, so the two playheads sit on the **same vertical line** and both
resize together with the window. Today the strip's fixed 150pt left header
(mute + filename) pushes its ruler ~158pt inward while the waveform is inset
only 16pt, so the playheads never coincide.

## Decisions (locked with the user)

- **Remove the LTC strip header.** The ruler spans the full width, sharing the
  waveform's horizontal insets, so the two playhead tracks occupy the identical
  x-range.
- **Move the per-clip LTC mute** out of the strip into the **media right-click
  menu** (same menu as "Show in Finder"), shown when LTC routing is enabled.
  (It's also already editable in the Edit Media sheet.)
- **Drop the filename** from the strip — the active clip name is already shown
  in the inspector header and the preview.
- The strip stays inset 16pt (matching the waveform); the transport bar below it
  stays full-bleed (accepted trade-off for exact playhead alignment).

## Architecture

Both playheads already map time→x via `CueMarkersGeometry.position(forTime:
width:duration:)`. Collinearity therefore holds iff the waveform track and the
LTC ruler share the **same width and left origin** — i.e. the same horizontal
inset from the same (detail-column) edge.

### Shared inset (`OnlyCue/UI/PreviewLayout.swift`)

- Introduce `PreviewLayout.trackHorizontalInset` (= `DS.Space.lg`, 16pt) as the
  single source of truth for the waveform/LTC track inset.
- `PreviewPane` uses it for the waveform ZStack's `.padding(.horizontal, …)`.
- The LTC strip is padded by the same constant, so its ruler = the waveform's
  x-range.

### LTC strip (`OnlyCue/UI/LTCStrip.swift`)

- Remove the `header` (mute button + "LTC · filename"), `laneHeaderWidth`, and
  `onToggleMute`. Body = the ruler only, full width, with the `rulerLeadingInset`
  removed (the waveform has no internal inset), so the ruler spans the padded
  width edge-to-edge and the playhead maps across it.

### Mute relocation (`OnlyCue/UI/ItemListPane.swift`)

- Add a "Mute/Unmute LTC for this clip" item to the media context menu, gated on
  `LTCRoutingStore.shared.settings.isEnabled`, calling the existing
  `CueCommands.setLTCMuted(...)`.

### Placement (`OnlyCue/UI/DocumentView.swift`)

- Pad the LTC strip with `PreviewLayout.trackHorizontalInset` where it's inserted
  (`ltcStripIfEnabled`), matching the waveform; the transport stays full-bleed.

### Compatibility

No `ProjectModel` / schema change. `MediaItem.ltcMuted` and the LTC output path
are untouched — only the mute's UI entry point moves.

## Testing

- **Unit:** pin `PreviewLayout.trackHorizontalInset` (= `DS.Space.lg`), the
  single inset both tracks use; `CueMarkersGeometry.position` already guarantees
  equal time→x for equal width (existing tests).
- **UI (XCUITest):** with LTC enabled, seek to a known fraction and screenshot —
  the LTC playhead sits directly beneath the waveform playhead (visual
  collinearity). The mute toggle appears in the media context menu.
- **Not unit-tested:** pixel collinearity (a layout property) — screenshot-
  verified.

## Hard-rules check

No schema change, no App Sandbox, no embedded media, macOS 14.0 floor untouched.

## Out of scope

Horizontal waveform zoom; making the transport bar share the inset.
