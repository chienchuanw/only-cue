# OnlyCue

A native macOS application for lighting designers and show programmers, inspired by [CuePoints](https://cuepoints.com/). Import a media file (audio or video), preview it, and lay out a **cue list** — an ordered set of named, color-coded markers anchored to timestamps — to plan and communicate timing for live shows or TV.

## Status

C1 bootstrap, C2 CI, E1 skeleton, and E2 player core have shipped ([#14](https://github.com/chienchuanw/only-cue/pull/14), [#15](https://github.com/chienchuanw/only-cue/pull/15), [#16](https://github.com/chienchuanw/only-cue/pull/16), [#17](https://github.com/chienchuanw/only-cue/pull/17)). Document-based app foundation plus first media playback: `ProjectModel`/`Cue`/`MediaReference` Codable types, `CueListDocument` (`ReferenceFileDocument`), `.cuelist` UTType, `DocumentGroup` wiring, `PlayerEngine` wrapping `AVPlayer` with `@Observable` state, `TransportBar` SwiftUI view, and `TimeFormat.hms` HH:MM:SS.mmm formatter. Next up: [#5](https://github.com/chienchuanw/only-cue/issues/5) (E3 media import — file picker, drag-drop, security-scoped bookmarks). Track everything on the [issue board](https://github.com/chienchuanw/only-cue/issues).

## Build

```bash
brew install xcodegen swiftlint   # one-time
xcodegen generate                  # produces OnlyCue.xcodeproj from project.yml
open OnlyCue.xcodeproj
```

`OnlyCue.xcodeproj/` is generated and gitignored — `project.yml` is the source of truth.

## Documents

Read in this order:

1. [`docs/vision.md`](docs/vision.md) — what we're building and for whom
2. [`docs/mvp-scope.md`](docs/mvp-scope.md) — what's in and out for v1
3. [`docs/architecture.md`](docs/architecture.md) — modules, layout, key APIs
4. [`docs/data-model.md`](docs/data-model.md) — `ProjectModel`, `Cue`, file format
5. [`docs/build-sequence.md`](docs/build-sequence.md) — phased build order
6. [`docs/verification.md`](docs/verification.md) — how to know it works
7. [`docs/roadmap.md`](docs/roadmap.md) — phase 2+ and our differentiator
8. [`docs/decisions.md`](docs/decisions.md) — ADR log of locked choices

## Stack at a glance

| | |
|---|---|
| Language | Swift 5.10+ |
| UI | SwiftUI (`@Observable`, `DocumentGroup`) |
| Media | AVFoundation (`AVPlayer`, `AVAssetReader`) |
| Min OS | macOS 14 (Sonoma) |
| Project file | `.cuelist` (JSON) |
| Distribution | Developer ID signed + notarized DMG |

## Reference

- CuePoints (the inspiration): https://cuepoints.com/
