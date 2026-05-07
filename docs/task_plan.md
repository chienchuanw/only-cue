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
| [#7](https://github.com/chienchuanw/only-cue/issues/7) | E5 waveform — async peak generation, cache, `Canvas` rendering | ⏭️ next |
| [#8](https://github.com/chienchuanw/only-cue/issues/8) | E6 cue list pane | pending |
| [#9](https://github.com/chienchuanw/only-cue/issues/9) | E7 add/edit/delete cues | pending |
| [#10](https://github.com/chienchuanw/only-cue/issues/10) | E8 cue markers | pending |
| [#11](https://github.com/chienchuanw/only-cue/issues/11) | E9 polish | pending |
| [#12](https://github.com/chienchuanw/only-cue/issues/12) | E10 distribution (blocked by #13) | pending |
| [#13](https://github.com/chienchuanw/only-cue/issues/13) | C3 release pipeline | pending |

## Recommended order

1. ~~**#2 (C2 CI)** — green-build gate.~~ Done.
2. ~~**#3 (E1 skeleton)** — `ProjectModel`/`CueListDocument`/`DocumentGroup`.~~ Done.
3. ~~**#4 (E2 player core)** — `PlayerEngine`, `TransportBar`, `TimeFormat.hms`.~~ Done.
4. ~~**#5 (E3 media import)** — `fileImporter` + drag-drop + bookmarks + `MediaImporter` command.~~ Done.
5. ~~**#6 (E4 video preview)** — `AVPlayerLayerView` + `PreviewPane`.~~ Done.
6. **#7 (E5 waveform)** — `WaveformGenerator` (async peak reduction via `AVAssetReader` + `AVAssetReaderTrackOutput`), `WaveformView` rendering peaks via SwiftUI `Canvas`, on-disk peak cache keyed by asset hash. First piece of significant async background work in the codebase. Watch out for: cancellation when the user re-imports mid-generation, memory bounds on large files, cache key stability across saves.
7. **#8..#11 (E6..E9)** — feature epics in build-sequence order. Leaves expanded JIT.
8. **#13 (C3) → #12 (E10)** — release pipeline, then ship.

## Phase 2 / Phase 3 milestones

Empty placeholders. Phase 2 (LTC, templates, export, custom shortcuts) and Phase 3 (the differentiator — TBD) get their own epics added when the MVP is feature-complete. See `docs/roadmap.md`.
