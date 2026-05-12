# OnlyCue

A native macOS application for lighting designers and show programmers, inspired by [CuePoints](https://cuepoints.com/). Import a media file (audio or video), preview it, and lay out a **cue list** — an ordered set of named, color-coded markers anchored to timestamps — to plan and communicate timing for live shows or TV.

## Table of Contents

- [Install](#install)
- [Status](#status)
- [Build](#build)
- [Documents](#documents)
- [Stack at a glance](#stack-at-a-glance)
- [Reference](#reference)

## Install

Download the latest DMG from the [releases page](https://github.com/chienchuanw/only-cue/releases) and follow these steps:

1. Open `OnlyCue-x.y.z.dmg` and drag **OnlyCue** into your Applications folder.
2. Eject the DMG.
3. **First launch:** in Finder, right-click (or Control-click) `OnlyCue.app` and choose **Open**. macOS will warn that the developer can't be verified — click **Open** anyway. Future launches are silent.

Why the right-click step? OnlyCue is currently distributed without a paid Apple Developer ID signature. The `.app` is ad-hoc signed and unmodified; right-clicking → Open is the standard macOS bypass. If you'd rather avoid that step, [build from source](#build).

System requirements: macOS 14 (Sonoma) or later, Apple silicon or Intel.

## Status

### Current release

**MVP shipped — [v0.1.0](https://github.com/chienchuanw/only-cue/releases/tag/v0.1.0).** All 13 MVP issues closed via PRs [#14–#26](https://github.com/chienchuanw/only-cue/pulls?q=is%3Apr+is%3Amerged).

### Shipped beyond MVP (on `dev`)

| Area | What's in |
|---|---|
| **Post-MVP enhancements** | Multi-media items per project (schema v2 with auto-migration, sidebar with drag-reorder, multi-file picker, per-item cues, background waveform prewarm); waveform strip beneath video imports; draggable playhead with HH:MM:SS scrub label; horizontal waveform zoom (1×–16× via trackpad pinch and `⌘=`/`⌘-`/`⌘0`) with auto-follow during playback. |
| **Epic [#32](https://github.com/chienchuanw/only-cue/issues/32) — cue model rework** | **Complete.** First-class `CuePointType`, user-facing `Cue.cueNumber` with mid-point insertion, required `Cue.fadeTime` (split-fade syntax), cue inspector pane, "Manage Types…" sheet, number-key cue creation. Schema settled at v6 with deterministic migrations from v1+. |
| **Epic [#34](https://github.com/chienchuanw/only-cue/issues/34) — console export** | **Complete.** File → Export Cues… (`⇧⌘E`) → sheet with a format picker (CSV / TSV / grandMA3 / grandMA2 — the last two best-effort, no authoritative format docs in-repo) and per-`CuePointType` filter. Two orthogonal pure functions (`CueExportFilter` + `CueCSVExporter`) plus an AppKit save action; golden-file tests pin all four targets. ADR-013/014. |
| **Epic [#35](https://github.com/chienchuanw/only-cue/issues/35) — OSC remote control** | **Complete.** Receive-only OSC server (UDP, `Network.framework`, hand-rolled OSC 1.0 parser — no dependency); Settings → OSC enable toggle + listen port; transport (`/onlycue/play\|pause\|stop\|skip\|locate`) and cue (`/cue/add\|next\|prev`) commands; `Tools → OSC Monitor…` sheet with a live message tail + copyable address list; Bitfocus Companion / StreamDeck / grandMA3 macro reference in [`docs/osc-companion-ma3.md`](docs/osc-companion-ma3.md). Per-document server (one document responds — ADR-016). |
| **Epic [#36](https://github.com/chienchuanw/only-cue/issues/36) — timeline UX polish** | **In progress.** ↑/↓ keyboard step to prev/next cue; ⌘⌥=/⌘⌥-/⌘⌥0 vertical waveform zoom; single hover-revealed magnifier on the right edge for two-axis click-and-drag zoom (Shift-locks to dominant axis, double-click resets both); `S` snaps the selected cue to the playhead; ⌥←/⌥→ nudge it by a configurable step; `⌘D` duplicates the cue at the playhead. Waveform gain control and the Cmd/Shift multi-select model still pending. |
| **Epic [#37](https://github.com/chienchuanw/only-cue/issues/37) — timeline breakdown view** | **Complete.** `View → Show Timeline Breakdown` (`⇧⌘B`) swaps the preview's timeline for one lane per visible `CuePointType` — each with that Type's markers, a hide button, and a playhead line spanning all lanes; "+N hidden lanes" restores hidden ones. Lane visibility (`CuePointType.isVisible`) persists in `.cuelist` with no schema bump (ADR-017). Layout covered by `TimelineBreakdownLayout(Fidelity)Tests` + `CueCommandsVisibilityTests` (incl. a v3-migrated `.cuelist` fixture); a media-loaded UI screenshot fixture remains the one deferred item. |
| **Epic [#38](https://github.com/chienchuanw/only-cue/issues/38) — notes overlay** | **In progress.** HUD-style overlay rendering the active cue's notes on top of the preview; Tools-menu appearance sheet customising position, font scale (0.75×–3×), text color, optional solid background, optional cue-number prefix; restore-defaults button. |
| **Epic [#39](https://github.com/chienchuanw/only-cue/issues/39) — templates** | **Complete.** Save the project's `CuePointType` set as a `.cuelist-template` under `~/Documents/OnlyCue/Templates/`; File → Load Template… merges a template into the open project (append + fresh UUIDs so existing cues' `typeID` references never break — ADR-015); File → New from Template… starts a new document pre-loaded with a template's Type set. |
| **Stand-alone leaves** | Cue inspector commits drafts on outside-click (window-scoped `NSEvent` monitor); File → Import Media… menu entry with ⌘O (canonical menu owner); ⇧⌘P "pause at each cue" mode; ⇧⌘N notes-overlay toggle; clickable empty-preview placeholder. |
| **Release pipeline** | Self-serve: `bash scripts/build-release.sh && bash scripts/make-dmg.sh` produces a drag-installable DMG. Default `RELEASE_MODE=unsigned` is free-tier-friendly (ad-hoc signed). `RELEASE_MODE=signed` opt-in for Developer ID + notarization once on a paid Apple Developer Program. Procedure in [`docs/release.md`](docs/release.md). |

### In progress / next

- **Phase 2 — Pro handoff** — nine epics filed; #32, #34, #35, #37 and #39 complete; #36 and #38 in flight. Open epics not yet started: [#33](https://github.com/chienchuanw/only-cue/issues/33) LTC, [#40](https://github.com/chienchuanw/only-cue/issues/40) custom shortcuts editor.
- **Live status** — [`docs/task_plan.md`](docs/task_plan.md) is the source of truth for what's open / in flight.
- **Append-only history** — [`docs/progress.md`](docs/progress.md) carries the per-PR narrative with rationale for every load-bearing decision.
- **Issue board** — [github.com/chienchuanw/only-cue/issues](https://github.com/chienchuanw/only-cue/issues).

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

### Run tests and lint locally

```bash
xcodebuild test -project OnlyCue.xcodeproj -scheme OnlyCue -destination 'platform=macOS'
swiftlint --strict
```

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
9. [`docs/task_plan.md`](docs/task_plan.md) — live phase tracker
10. [`docs/progress.md`](docs/progress.md) — append-only per-PR narrative

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
