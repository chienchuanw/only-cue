# Task Plan

Working source of truth for what's left. Sourced from the [GitHub issue board](https://github.com/chienchuanw/only-cue/issues) and the build sequence. When in doubt, the issues are authoritative.

## Active milestone — MVP ✅ shipped (v0.1.0)

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
| [#10](https://github.com/chienchuanw/only-cue/issues/10) | E8 cue markers — draw on waveform, drag to retime, click to seek | ✅ shipped (PR #23) |
| [#11](https://github.com/chienchuanw/only-cue/issues/11) | E9 polish | ✅ shipped (PR #24) |
| [#13](https://github.com/chienchuanw/only-cue/issues/13) | C3 release pipeline | ✅ shipped (PR #25) |
| [#12](https://github.com/chienchuanw/only-cue/issues/12) | E10 distribution | ✅ shipped (PR #26 + [v0.1.0](https://github.com/chienchuanw/only-cue/releases/tag/v0.1.0)) |

## Recommended order

1. ~~**#2 (C2 CI)** — green-build gate.~~ Done.
2. ~~**#3 (E1 skeleton)** — `ProjectModel`/`CueListDocument`/`DocumentGroup`.~~ Done.
3. ~~**#4 (E2 player core)** — `PlayerEngine`, `TransportBar`, `TimeFormat.hms`.~~ Done.
4. ~~**#5 (E3 media import)** — `fileImporter` + drag-drop + bookmarks + `MediaImporter` command.~~ Done.
5. ~~**#6 (E4 video preview)** — `AVPlayerLayerView` + `PreviewPane`.~~ Done.
6. ~~**#7 (E5 waveform)** — `WaveformGenerator` + `WaveformCache` + `WaveformView`.~~ Done.
7. ~~**#8 (E6 cue list pane)** — `CueListPane` + `CueRowView` + `Color+Hex` + minimal `CueCommands` seam.~~ Done.
8. ~~**#9 (E7 add/edit/delete cues)** — `CueCommands` extended with 5 undoable mutations + UI wiring (M, ⌘Z, double-click rename, palette popover, ⌫).~~ Done.
9. ~~**#10 (E8 cue markers)** — overlay vertical markers + colored caps on the waveform, drag to retime via `CueCommands.retime`, tap to seek via `engine.seek`.~~ Done.
10. ~~**#11 (E9 polish)** — relink alert, navigation subtitle, Space/←/→ shortcuts, placeholder app icon, About panel, first-launch sheet.~~ Done.
11. ~~**#13 (C3 release pipeline)** — `scripts/build-release.sh`, `scripts/make-dmg.sh`, `docs/release.md`. Defaults to free-tier `RELEASE_MODE=unsigned` (ad-hoc signed .app + plain DMG); `RELEASE_MODE=signed` opt-in for Developer ID + notarization once we upgrade.~~ Done.
12. ~~**#12 (E10 distribution)** — README install section, `docs/release-notes/0.1.0.md`, free-tier-aware verification doc; tagged `v0.1.0` on `008cf03`, built the DMG via the C3 pipeline, attached to a GitHub Release.~~ Done — [v0.1.0 published](https://github.com/chienchuanw/only-cue/releases/tag/v0.1.0).

## Post-MVP enhancements

Targeted gap fixes on the shipped MVP. Not part of phase 2 epics.

| Issue | Title | Status |
|---|---|---|
| [#27](https://github.com/chienchuanw/only-cue/issues/27) | Display waveform for video imports — stack waveform strip beneath video frame | ✅ shipped (PR #28) |
| [#29](https://github.com/chienchuanw/only-cue/issues/29) | Waveform playhead indicator with drag-to-scrub — vertical line + HH:MM:SS label, both audio and video strips | ✅ shipped (PR #30) |
| [#31](https://github.com/chienchuanw/only-cue/issues/31) | Multi-media items per project — schema v2 with auto-migration, left sidebar with drag-reorder, multi-file import, per-item cues, waveform prewarm | ✅ shipped (PR #41) |
| [#42](https://github.com/chienchuanw/only-cue/issues/42) | Waveform horizontal zoom (1×–16× via trackpad pinch + ⌘=/⌘-/⌘0) with auto-follow during playback; thinner playhead line | ✅ shipped (PR #43) |

## Active milestone — Phase 2 — Pro handoff (parity push)

Filed 2026-05-08 from the CuePoints competitive-gap brainstorm. Positioning: "pro-handoff parity" — the smallest set that lets a programmer leave CuePoints. Tier-C differentiator deferred to Phase 3.

| Issue | Title | Pri | Status |
|---|---|---|---|
| [#32](https://github.com/chienchuanw/only-cue/issues/32) | Cue model rework — CuePoint Types, Cue ID, fade time | p1 | 🟡 in progress (leaves [#44](https://github.com/chienchuanw/only-cue/issues/44) → PR #45 [CuePointType + schema v3], [#46](https://github.com/chienchuanw/only-cue/issues/46) → PR #47 [Cue.cueNumber + schema v4], [#50](https://github.com/chienchuanw/only-cue/issues/50) → PR #51 [Cue.fadeTime + schema v5], [#52](https://github.com/chienchuanw/only-cue/issues/52) → PR #53 [cue inspector pane], [#54](https://github.com/chienchuanw/only-cue/issues/54) → PR #55 [color from Type + schema v6]) |
| [#33](https://github.com/chienchuanw/only-cue/issues/33) | LTC generation + audio routing | p1 | ⚪ open |
| [#34](https://github.com/chienchuanw/only-cue/issues/34) | Console export — CSV, MA2, MA3 (depends on #32) | p1 | ⚪ open |
| [#35](https://github.com/chienchuanw/only-cue/issues/35) | OSC remote control (Companion / MA3 / StreamDeck) | p1 | ⚪ open |
| [#36](https://github.com/chienchuanw/only-cue/issues/36) | Timeline UX polish (zoom/gain/snap/nudge/multi-select/inter-cue nav) | p1 | ⚪ open |
| [#37](https://github.com/chienchuanw/only-cue/issues/37) | Timeline breakdown view (depends on #32) | p1 | ⚪ open |
| [#38](https://github.com/chienchuanw/only-cue/issues/38) | Notes overlay on video preview | p1 | ⚪ open |
| [#39](https://github.com/chienchuanw/only-cue/issues/39) | Templates — CuePoint Type sets (depends on #32) | p2 | ⚪ open |
| [#40](https://github.com/chienchuanw/only-cue/issues/40) | Custom keyboard shortcuts editor | p2 | ⚪ open |

### Remaining leaves of #32

Filed JIT via `gh-dev` as work picks up. Each becomes its own issue + PR.

- [x] spec — `docs/data-model.md#schema-v3` + ADR-009 (bundled into #44 → PR #45)
- [x] model — introduce `CuePointType` (#44 → PR #45)
- [x] migration — v2→v3 transform (#44 → PR #45)
- [x] model — editable `Cue.cueNumber` with mid-point insertion rule + schema v4 + v3→v4 migration (#46 → PR #47)
- [x] model — `Cue.fadeTime` with split-fade syntax (`1/2` → `(in: 1.0, out: 2.0)`) + schema v5 + v4→v5 migration (#50 → PR #51)
- [x] ui — cue inspector pane (edit Type, cueNumber, fade, notes) — VSplitView below cue list, four new `CueCommands` setters, pure `CueInspectorCommit` parse-or-revert helper, focused-aware draft sync (#52 → PR #53)
- [x] cleanup — UI reads color from Type; remove transitional `Cue.colorHex` — `ProjectModel.colorHex(for:)` resolver, `CueRowView`/`CueMarkersOverlay` rewired, palette popover and `CueCommands.recolor` deleted, schema v6 with v5→v6 migration (#54 → PR #55). Type management UI is the natural follow-up leaf to restore per-cue color flexibility.
- [ ] shortcut — number-key cue creation (1–0 binds to a Type via the keymap)

### Carry-overs from PR #47 review (deferred substantive notes)

- [ ] [#48](https://github.com/chienchuanw/only-cue/issues/48) — stable-sort tie-breaker on equal `cue.time` in `assignCueNumbersBySort`
- [ ] [#49](https://github.com/chienchuanw/only-cue/issues/49) — drop the `cueNumber: 0` placeholder in `LegacyCue.toCue` / `LegacyV3Cue.toCue` (PendingCue tuple / struct so the type system enforces the invariant)

## Phase 3 milestone — Differentiator

Empty until Phase 2 ships. Three candidates from the roadmap: AI-assisted cueing, real-time collaboration, push/pull console integration. We pick one when Phase 2 is in user hands and we know which gap matters most.
