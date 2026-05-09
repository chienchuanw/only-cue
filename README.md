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

**MVP shipped — [v0.1.0](https://github.com/chienchuanw/only-cue/releases/tag/v0.1.0).** All 13 MVP issues closed via PRs [#14–#26](https://github.com/chienchuanw/only-cue/pulls?q=is%3Apr+is%3Amerged). Post-MVP enhancements landing on `dev`: PR [#28](https://github.com/chienchuanw/only-cue/pull/28) added a waveform strip beneath video imports for cue-marker editing, PR [#30](https://github.com/chienchuanw/only-cue/pull/30) added a draggable playhead indicator with HH:MM:SS scrub label that works on both audio and video waveforms, PR [#41](https://github.com/chienchuanw/only-cue/pull/41) extended `.cuelist` to hold multiple media items per project (schema v2; v1 auto-migrates) with a left sidebar that supports drag-reorder, multi-file picker + drop, and per-item independent cue lists (plus background `WaveformPrewarmer` for instant first-click rendering), and PR [#43](https://github.com/chienchuanw/only-cue/pull/43) added horizontal waveform zoom (1×–16× via trackpad pinch and `⌘=` / `⌘-` / `⌘0`) with auto-follow during playback. The release pipeline is self-serve: `bash scripts/build-release.sh && bash scripts/make-dmg.sh` produces a drag-installable DMG. The default `RELEASE_MODE=unsigned` path is free-tier-friendly: the `.app` is ad-hoc-signed (so users see a normal "developer cannot be verified" Gatekeeper prompt cleared by right-click → Open, not the misleading "is damaged" error). `RELEASE_MODE=signed` opt-in produces a Gatekeeper-clean Developer ID + notarized + stapled DMG once we upgrade to a paid Apple Developer Program. Full procedure in [`docs/release.md`](docs/release.md). **Phase 2 — Pro handoff has begun:** nine epics filed (#32–#40) covering CuePoint Types, LTC + audio routing, console export (CSV/MA2/MA3), OSC remote, timeline UX polish, breakdown view, notes overlay, templates, and a custom shortcuts editor. Epic #32 is complete — all seven leaves have landed: PR [#45](https://github.com/chienchuanw/only-cue/pull/45) introduced `CuePointType` as a first-class entity referenced by every cue (schema v3 with v2→v3 auto-migration), PR [#47](https://github.com/chienchuanw/only-cue/pull/47) added a user-facing `Cue.cueNumber: Double` (e.g. 1, 1.5, 2) consumable by lighting consoles, with a stable mid-point insertion rule that never shifts existing numbers (schema v4 with v3→v4 auto-migration that assigns sequential numbers by time order), PR [#51](https://github.com/chienchuanw/only-cue/pull/51) added required `Cue.fadeTime` — a `FadeTime` value struct that carries both symmetric (`1.5`) and split (`1/2` → in: 1, out: 2) fades, with a pure parser/formatter pair and a `FadeTime.zero` no-fade constant (schema v5 with v4→v5 auto-migration that backfills `.zero` on every existing cue; v1/v2/v3 chains backfill at the cue boundary so any pre-v5 source lands on a valid v5 model), PR [#53](https://github.com/chienchuanw/only-cue/pull/53) added a cue inspector pane below the existing cue list (vertical split, draggable) that finally surfaces and edits all of the schema fields the prior three leaves added — Type picker, cueNumber TextField, name, fadeTime (parsed via `FadeTime.parse`, redisplays in canonical form), and a multi-line notes editor — with focused-aware draft sync that protects in-progress typing from external mutations (e.g. marker drag retime), four new `CueCommands` setters (`setType` / `setCueNumber` / `setFadeTime` / `setNotes`) routed through a single `updateCue` helper, a pure `CueInspectorCommit` parse-or-revert helper that lets the field-commit logic be TDD'd without spinning up a SwiftUI host, and a small shared `CueColorSwatch` reused between the Type picker and the cue row's color popover, PR [#55](https://github.com/chienchuanw/only-cue/pull/55) dropped the transitional `Cue.colorHex` field (schema v6 with v5→v6 auto-migration that strips it; pre-v6 chains all updated to drop the field at the legacy `toCue()` boundary) and rewired every UI site that paints a cue color to resolve via the cue's `CuePointType` through a new `ProjectModel.colorHex(for:)` helper — fixing the picker-mismatch UX bug surfaced by PR #53 (changing Type via the inspector now actually updates the row swatch and waveform marker), at the cost of removing the per-row palette popover, PR [#57](https://github.com/chienchuanw/only-cue/pull/57) restored that flexibility with a "Manage Types…" sheet driven from the cue inspector — `ColorPicker` per row, name TextField, hotkey Picker (none / 0–9) with move semantics on conflict, and `✕` delete with a confirm dialog that reassigns referenced cues to the default Type as one undo group; five new `CueCommands` mutations (`addCuePointType` / `setCuePointTypeName` / `setCuePointTypeColor` / `setCuePointTypeHotkey` / `removeCuePointType`) routed through two new undo seams (narrow `mutateTypes` plus a wider `mutateProject` that intentionally excludes `activeItemID` so undoing a cross-domain delete doesn't silently revert item selection), a pure `TypeDeletionPlan` helper that handles the "delete the default → next Type absorbs" edge case, and a shared `CuePointType.defaultPalette` so future callers can't drift, and PR [#59](https://github.com/chienchuanw/only-cue/pull/59) closed the Type-driven cue-creation loop end-to-end by binding plain digit keys `1`–`0` to `CuePointType.hotkey`: `DocumentView` mounts ten hidden zero-frame Buttons via SwiftUI's `.keyboardShortcut(_:modifiers:)` (which automatically yields to focused TextFields, so typing into the inspector or the Manage Types sheet still works as expected), each routing through a new `ProjectModel.cuePointType(forHotkey:)` lookup to a new `CueCommands.addCueAtPlayhead(time:typeID:document:undoManager:)` overload that guards against dangling typeIDs and shares a private `appendCue` helper with the default-Type form (UI + commands only — no schema bump). The data model has settled at schema v6 with no further bumps planned for the parity push. PR [#60](https://github.com/chienchuanw/only-cue/pull/60) cleaned up the first carry-over from PR #47's review with a structural refactor of the v1/v2/v3 migrations: `LegacyCue.toCue` / `LegacyV3Cue.toCue` no longer write a `cueNumber: 0` sentinel that `assignCueNumbersBySort` would later overwrite (a placeholder that became indistinguishable from real data after `addCueAtPlayhead` learned to produce `cueNumber: 0` when inserting before cue #1). Instead, both methods now return a new `private struct PendingCue` (every `Cue` field except `cueNumber`), and `assignCueNumbersBySort` takes `[PendingCue]` per-item and emits `[Cue]` in one pass — making it physically impossible for a future migration to construct a `Cue` from a pre-cueNumber legacy source without going through the helper (a forgotten call now fails to compile rather than silently producing zeros). PR [#61](https://github.com/chienchuanw/only-cue/pull/61) closed the second carry-over by tie-breaking `assignCueNumbersBySort` on `id.uuidString` lexicographic order when two cues share a `time`: Swift's `Array.sorted(by:)` isn't spec-guaranteed stable, so without the rule the `cueNumber` for equal-time cues would be implementation-defined; with it, re-running the migration on the same JSON always produces the identical assignment. Both PR #47 review carry-overs are now done. PR [#63](https://github.com/chienchuanw/only-cue/pull/63) closed a third pre-existing simplify finding (twice deferred — once on PR #60, once on PR #61) by dropping the dead `let colorHex: String` declaration from all four legacy cue Decodable structs (`LegacyCue` / `LegacyV3Cue` / `LegacyV4Cue` / `LegacyV5Cue`): the field had been decoded from pre-v6 JSON since PR #55 made color a Type-derived fact, but never read after the `toCue` / `toPendingCue` boundary — Swift's `Decodable` synthesis was the only reason it stayed. Removing it makes the legacy decoders lenient (pre-v6 JSON whose cues are missing `colorHex` now decodes cleanly instead of throwing `DecodingError.keyNotFound`, which is the more permissive contract for old hand-edited fixtures and forward-port scripts) and shrinks the pre-v6 footprint by four stored properties. With the post-#32 cleanup track wrapped, **Phase 2 leaf work has resumed**: PR [#65](https://github.com/chienchuanw/only-cue/pull/65) is the first leaf carved out of [epic #36](https://github.com/chienchuanw/only-cue/issues/36) (timeline UX polish), wiring `↑` / `↓` keyboard shortcuts to step the playhead to the previous / next cue (by `time`) in the active media item — a pure-function `MediaItem.cue(steppingFrom:direction:) -> Cue?` helper (with strict `<` / `>` comparison so the cue at the exact playhead time is skipped, ensuring repeated step presses always advance) plus a new hidden-button `ZStack` (mirroring `transportShortcuts` and `digitShortcuts` — three uses now confirms the dispatch shape) routes through the same `Task`-cancellation seek pattern as the existing `←` / `→` frame-stepping; UI + commands only, no schema bump, no wrap-around at the ends of the cue list. See [`docs/roadmap.md`](docs/roadmap.md) for the parity slate and [the issue board](https://github.com/chienchuanw/only-cue/issues) for live status.

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
