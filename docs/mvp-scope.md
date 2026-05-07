# MVP Scope

A **thin slice** of the cue-planning workflow. Everything below should work end-to-end before we ship; nothing else is required for v1.

## In scope

| # | Capability | Acceptance |
|---|---|---|
| 1 | Open the app | Empty document window appears |
| 2 | Import media (`⌘O` or drag-drop) | Audio (`.mp3`, `.wav`, `.aac`, `.m4a`, `.aiff`) and video (`.mp4`, `.mov`) load via `AVPlayer` |
| 3 | Preview pane | Audio shows a waveform; video shows the picture and a waveform strip beneath it |
| 4 | Transport controls | Play / pause / scrub / jump start / jump end / time readout `HH:MM:SS.mmm` |
| 5 | Cue list panel | Right-side list showing `#`, name, time, color swatch |
| 6 | Add cue at playhead | `M` key or button; appends to list |
| 7 | Edit cue | Inline rename, recolor, retype time, delete |
| 8 | Click cue → seek | Tapping a row moves playhead to that cue's time |
| 9 | Cue markers on waveform | Draw on timeline; drag to retime; click to seek |
| 10 | Save / Open | `.cuelist` JSON document via `DocumentGroup` |
| 11 | Reopen restores media | Stored security-scoped bookmark resolves on open |
| 12 | Undo / redo | All cue mutations go through `UndoManager` |

## Out of scope (deferred to phase 2+)

- LTC / MTC timecode generation or playback
- OSC / MIDI to lighting consoles
- Templates and template library
- Custom keyboard-shortcut editor
- Export to CSV / EDL / Timecode XML / console-specific formats
- Multi-track or multi-media documents
- Real-time collaboration
- Beat detection / AI-assisted cueing
- Mac App Store distribution (we ship direct DMG only)
- iOS / iPad / web

## Why this slice

Each item exists because removing it breaks the loop "import → mark → save → reopen". Anything that can be removed without breaking that loop has been removed.
