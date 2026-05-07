# Task Plan

Working source of truth for what's left. Sourced from the [GitHub issue board](https://github.com/chienchuanw/only-cue/issues) and the build sequence. When in doubt, the issues are authoritative.

## Active milestone — MVP

| Issue | Title | Status |
|---|---|---|
| [#1](https://github.com/chienchuanw/only-cue/issues/1) | C1 bootstrap | ✅ shipped (PR #14) |
| [#2](https://github.com/chienchuanw/only-cue/issues/2) | C2 CI — GitHub Actions, build + XCTest + XCUITest | ✅ shipped (PR #15) |
| [#3](https://github.com/chienchuanw/only-cue/issues/3) | E1 skeleton — `DocumentGroup`, `ProjectModel`, `.cuelist` UTType | ✅ shipped (PR #16) |
| [#4](https://github.com/chienchuanw/only-cue/issues/4) | E2 player core — `AVPlayer` wrapper, transport bar, time publisher | ✅ shipped (PR #17) |
| [#5](https://github.com/chienchuanw/only-cue/issues/5) | E3 media import — file picker, drag-drop, security-scoped bookmarks | ✅ shipped (PR #18) |
| [#6](https://github.com/chienchuanw/only-cue/issues/6) | E4 video preview — `AVPlayerLayer` via `NSViewRepresentable` | ✅ shipped (PR #19) |
| [#7](https://github.com/chienchuanw/only-cue/issues/7) | E5 waveform — async peak generation, cache, `Canvas` rendering | ✅ shipped (PR #20) |
| [#8](https://github.com/chienchuanw/only-cue/issues/8) | E6 cue list pane — read-only list bound to `ProjectModel.cues` | ✅ shipped (PR #21) |
| [#9](https://github.com/chienchuanw/only-cue/issues/9) | E7 add/edit/delete cues — M-key, inline rename, color picker, undoable | ✅ shipped (PR #22) |
| [#10](https://github.com/chienchuanw/only-cue/issues/10) | E8 cue markers — draw on waveform, drag to retime, click to seek | ⏭️ next |
| [#11](https://github.com/chienchuanw/only-cue/issues/11) | E9 polish | pending |
| [#12](https://github.com/chienchuanw/only-cue/issues/12) | E10 distribution (blocked by #13) | pending |
| [#13](https://github.com/chienchuanw/only-cue/issues/13) | C3 release pipeline | pending |

## Recommended order

1. ~~**#2 (C2 CI)** — green-build gate.~~ Done.
2. ~~**#3 (E1 skeleton)** — `ProjectModel`/`CueListDocument`/`DocumentGroup`.~~ Done.
3. ~~**#4 (E2 player core)** — `PlayerEngine`, `TransportBar`, `TimeFormat.hms`.~~ Done.
4. ~~**#5 (E3 media import)** — `fileImporter` + drag-drop + bookmarks + `MediaImporter` command.~~ Done.
5. ~~**#6 (E4 video preview)** — `AVPlayerLayerView` + `PreviewPane`.~~ Done.
6. ~~**#7 (E5 waveform)** — `WaveformGenerator` + `WaveformCache` + `WaveformView`.~~ Done.
7. ~~**#8 (E6 cue list pane)** — `CueListPane` + `CueRowView` + `Color+Hex` + minimal `CueCommands` seam.~~ Done.
8. ~~**#9 (E7 add/edit/delete cues)** — `CueCommands` extended with 5 undoable mutations + UI wiring (M, ⌘Z, double-click rename, palette popover, ⌫).~~ Done.
9. **#10 (E8 cue markers)** — overlay `Path`-drawn vertical markers on the waveform at each cue's x-position (`time / duration * width`). Draggable to retime (calls `CueCommands.retime`); tap to seek (calls `engine.seek`). Marker color = cue color. First UI to combine the waveform layer with cue mutations — design carefully so `WaveformContainer` stays a pure renderer and the marker overlay sits above it.
10. **#11 (E9 polish)** — empty states, missing-media relink alert, app icon, default keyboard shortcuts, About box. The relink work unblocks the deferred Gherkin scenarios from E5/E6 (waveform/cue cache hits on document reopen).
11. **#13 (C3) → #12 (E10)** — release pipeline, then ship.

## Phase 2 / Phase 3 milestones

Empty placeholders. Phase 2 (LTC, templates, export, custom shortcuts) and Phase 3 (the differentiator — TBD) get their own epics added when the MVP is feature-complete. See `docs/roadmap.md`.
