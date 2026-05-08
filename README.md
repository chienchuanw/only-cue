# OnlyCue

A native macOS application for lighting designers and show programmers, inspired by [CuePoints](https://cuepoints.com/). Import a media file (audio or video), preview it, and lay out a **cue list** — an ordered set of named, color-coded markers anchored to timestamps — to plan and communicate timing for live shows or TV.

## Install

Download the latest DMG from the [releases page](https://github.com/chienchuanw/only-cue/releases) and follow these steps:

1. Open `OnlyCue-x.y.z.dmg` and drag **OnlyCue** into your Applications folder.
2. Eject the DMG.
3. **First launch:** in Finder, right-click (or Control-click) `OnlyCue.app` and choose **Open**. macOS will warn that the developer can't be verified — click **Open** anyway. Future launches are silent.

Why the right-click step? OnlyCue is currently distributed without a paid Apple Developer ID signature. The `.app` is ad-hoc signed and unmodified; right-clicking → Open is the standard macOS bypass. If you'd rather avoid that step, [build from source](#build).

System requirements: macOS 14 (Sonoma) or later, Apple silicon or Intel.

## Status

**MVP shipped — [v0.1.0](https://github.com/chienchuanw/only-cue/releases/tag/v0.1.0).** All 13 MVP issues closed via PRs [#14–#26](https://github.com/chienchuanw/only-cue/pulls?q=is%3Apr+is%3Amerged). Post-MVP enhancements are landing on `dev`: PR [#28](https://github.com/chienchuanw/only-cue/pull/28) added a waveform strip beneath video imports for cue-marker editing, and PR [#30](https://github.com/chienchuanw/only-cue/pull/30) added a draggable playhead indicator with HH:MM:SS scrub label that works on both audio and video waveforms. The release pipeline is self-serve: `bash scripts/build-release.sh && bash scripts/make-dmg.sh` produces a drag-installable DMG. The default `RELEASE_MODE=unsigned` path is free-tier-friendly: the `.app` is ad-hoc-signed (so users see a normal "developer cannot be verified" Gatekeeper prompt cleared by right-click → Open, not the misleading "is damaged" error). `RELEASE_MODE=signed` opt-in produces a Gatekeeper-clean Developer ID + notarized + stapled DMG once we upgrade to a paid Apple Developer Program. Full procedure in [`docs/release.md`](docs/release.md). Phase 2 (LTC, templates, export, custom shortcuts, plus the differentiator) starts when the issue board picks up new epics — see [`docs/roadmap.md`](docs/roadmap.md). Track everything on the [issue board](https://github.com/chienchuanw/only-cue/issues).

## Build

```bash
brew install xcodegen swiftlint   # one-time
xcodegen generate                  # produces OnlyCue.xcodeproj from project.yml
open OnlyCue.xcodeproj
```

`OnlyCue.xcodeproj/` is generated and gitignored — `project.yml` is the source of truth.

### When to re-run xcodegen / clean the build folder

- **Re-run `xcodegen generate`** whenever `project.yml`, `Info.plist`, or the source folder structure changes (new top-level folder under `OnlyCue/`, new target, new pre-build script). Pulling a branch that touched any of those counts.
- **`⌘⇧K` (Clean Build Folder)** in Xcode after switching branches that changed Swift concurrency annotations or other compile-time invariants — Xcode's incremental build sometimes hangs on stale bitcode and surfaces it as a confusing build error (e.g., a Swift 6 `@MainActor` error on code that has already been fixed).
- **`⌘⇧⌥K` (Delete Derived Data)** if `⌘⇧K` doesn't clear the issue. Slower (full rebuild after) but resolves persistent stale-cache errors.

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
| Distribution | Ad-hoc signed DMG (Developer ID + notarization opt-in) |

## Reference

- CuePoints (the inspiration): https://cuepoints.com/
