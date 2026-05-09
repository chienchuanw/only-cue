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
| [#32](https://github.com/chienchuanw/only-cue/issues/32) | Cue model rework — CuePoint Types, Cue ID, fade time | p1 | ✅ shipped (all 7 leaves: [#44](https://github.com/chienchuanw/only-cue/issues/44) → PR #45 [CuePointType + schema v3], [#46](https://github.com/chienchuanw/only-cue/issues/46) → PR #47 [Cue.cueNumber + schema v4], [#50](https://github.com/chienchuanw/only-cue/issues/50) → PR #51 [Cue.fadeTime + schema v5], [#52](https://github.com/chienchuanw/only-cue/issues/52) → PR #53 [cue inspector pane], [#54](https://github.com/chienchuanw/only-cue/issues/54) → PR #55 [color from Type + schema v6], [#56](https://github.com/chienchuanw/only-cue/issues/56) → PR #57 [Type management sheet], [#58](https://github.com/chienchuanw/only-cue/issues/58) → PR #59 [number-key cue creation]) |
| [#33](https://github.com/chienchuanw/only-cue/issues/33) | LTC generation + audio routing | p1 | ⚪ open |
| [#34](https://github.com/chienchuanw/only-cue/issues/34) | Console export — CSV, MA2, MA3 (depends on #32) | p1 | ⚪ open |
| [#35](https://github.com/chienchuanw/only-cue/issues/35) | OSC remote control (Companion / MA3 / StreamDeck) | p1 | ⚪ open |
| [#36](https://github.com/chienchuanw/only-cue/issues/36) | Timeline UX polish (zoom/gain/snap/nudge/multi-select/inter-cue nav) | p1 | 🟡 in progress (4 leaves shipped: [#64](https://github.com/chienchuanw/only-cue/issues/64) → PR [#65](https://github.com/chienchuanw/only-cue/pull/65) ↑/↓ playhead step; [#66](https://github.com/chienchuanw/only-cue/issues/66) → PR [#67](https://github.com/chienchuanw/only-cue/pull/67) ⌘⌥ vertical zoom keyboard; [#68](https://github.com/chienchuanw/only-cue/issues/68) → PR [#69](https://github.com/chienchuanw/only-cue/pull/69) drag-below-waveform handle [superseded by #74]; [#73](https://github.com/chienchuanw/only-cue/issues/73) → PR [#74](https://github.com/chienchuanw/only-cue/pull/74) hover-revealed zoom rails — vertical-zoom bullet complete end-to-end) |
| [#37](https://github.com/chienchuanw/only-cue/issues/37) | Timeline breakdown view (depends on #32) | p1 | ⚪ open |
| [#38](https://github.com/chienchuanw/only-cue/issues/38) | Notes overlay on video preview | p1 | 🟡 in progress (1 leaf shipped: [#70](https://github.com/chienchuanw/only-cue/issues/70) → PR [#72](https://github.com/chienchuanw/only-cue/pull/72) `MediaItem.activeCue(at:)` helper + `NotesOverlayView` + View-menu `@AppStorage` toggle + architecture-doc section) |
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
- [x] cleanup — UI reads color from Type; remove transitional `Cue.colorHex` — `ProjectModel.colorHex(for:)` resolver, `CueRowView`/`CueMarkersOverlay` rewired, palette popover and `CueCommands.recolor` deleted, schema v6 with v5→v6 migration (#54 → PR #55).
- [x] ui — Type management sheet — "Manage Types…" button in cue inspector opens a modal with `ColorPicker` / name / hotkey / delete per row; five new `CueCommands` mutations through narrow `mutateTypes` and wide `mutateProject` undo seams; `TypeDeletionPlan` pure helper; `Color.toHex()` for sRGB-clamped round-trip; shared `CuePointType.defaultPalette` (#56 → PR #57).
- [x] shortcut — number-key cue creation (1–0 binds to a Type via `.keyboardShortcut`) — `DocumentView.digitShortcuts` mounts 10 hidden zero-frame Buttons; each routes through `ProjectModel.cuePointType(forHotkey:)` to a new `CueCommands.addCueAtPlayhead(time:typeID:...)` overload that guards against dangling typeIDs and shares a private `appendCue` helper with the default-Type form; SwiftUI yields the digit to focused TextFields automatically; unbound digit is a no-op (#58 → PR #59). **Epic #32 complete.**

### Carry-overs from PR #47 review (deferred substantive notes)

- [x] [#48](https://github.com/chienchuanw/only-cue/issues/48) → PR [#61](https://github.com/chienchuanw/only-cue/pull/61) — `assignCueNumbersBySort` tie-breaks equal `time`s on `id.uuidString` lexicographic order; ADR-010 amended; 2 new tests in `ProjectModelMigrationTieBreakTests.swift` (RED-first verified). **Both PR #47 review carry-overs now done.**
- [x] [#49](https://github.com/chienchuanw/only-cue/issues/49) → PR [#60](https://github.com/chienchuanw/only-cue/pull/60) — `private struct PendingCue` carries every `Cue` field except `cueNumber`; `assignCueNumbersBySort` now takes `[PendingCue]` and returns `[Cue]` per-item; the v1/v2/v3 migrations build per-item arrays and call the helper inline; v4/v5 untouched (they carry real cueNumbers). Pure structural refactor — type system now enforces the invariant.

### Post-#32 simplify-deferred cleanups

- [x] [#62](https://github.com/chienchuanw/only-cue/issues/62) → PR [#63](https://github.com/chienchuanw/only-cue/pull/63) — drop dead `let colorHex: String` from all four legacy cue Decodable structs (`LegacyCue` / `LegacyV3Cue` / `LegacyV4Cue` / `LegacyV5Cue`); the field had been decoded since pre-v6 days but never read after `toCue` / `toPendingCue`; removing it makes the legacy decoders lenient (pre-v6 JSON whose cues are missing `colorHex` now decodes cleanly instead of throwing `DecodingError.keyNotFound`); 1 new lenient-decode test in `ProjectModelMigrationLegacyDecodeTests.swift` (RED-first verified — pre-fix threw the keyNotFound error). **Three pre-existing simplify findings now done in three back-to-back PRs (#60 / #61 / #63); migration code at `ProjectModel.swift` is settled.**

### Epic #36 — Timeline UX polish (in progress)

- [x] [#64](https://github.com/chienchuanw/only-cue/issues/64) → PR [#65](https://github.com/chienchuanw/only-cue/pull/65) — `↑` / `↓` step playhead to prev / next cue (by `time`) in active media item; pure-function `MediaItem.cue(steppingFrom:direction:) -> Cue?` helper with `PlayheadStep` enum (strict `<`/`>` comparison so cue at exact playhead time is skipped; no wrap-around at ends); new `playheadStepShortcuts` ZStack mirrors `transportShortcuts` / `digitShortcuts` (3rd use confirms hidden-button pattern as canonical); 7 unit tests in new `MediaItemTests.swift`. UI + commands only — no schema bump. First Phase 2 leaf since post-#32 cleanup track wrapped.
- [x] [#66](https://github.com/chienchuanw/only-cue/issues/66) → PR [#67](https://github.com/chienchuanw/only-cue/pull/67) — vertical waveform zoom keyboard surface (`⌘⌥=` / `⌘⌥-` / `⌘⌥0`); new `WaveformVerticalZoomController` mirrors `WaveformZoomController` minus scroll/anchor; `WaveformView.halfHeight` calc gains scale + clip-at-midline; 3 menu items in View menu (Divider-separated from horizontal zoom); 3 new `Notification.Name` entries; vertical zoom resets on item switch (post-merge fix `f7dbcf1` — automated review caught a missed `verticalZoom.reset()` in `WaveformContainer.load()`); 5 unit tests. **Sub-leaf split of #36's "vertical waveform zoom (drag below the waveform)" bullet — keyboard surface ships first; drag gesture is the next sub-leaf.**
- [x] [#68](https://github.com/chienchuanw/only-cue/issues/68) → PR [#69](https://github.com/chienchuanw/only-cue/pull/69) — drag-below-waveform vertical zoom gesture; new `WaveformVerticalZoomController.applyDrag(translation:baseline:)` with multiplicative math (`baseline * pow(zoomStep, -translation/dragPixelsPerStep)`) at 60pt-per-step sensitivity (matches keyboard step rate); new `VerticalZoomDragHandle` view with hover-aware fill + `NSCursor.resizeUpDown` cue + `DragGesture(minimumDistance: 0)` baseline-captured drag; layout extracts `WaveformContainer.waveformBody(peaks:)` so outer `loaded(peaks:)` wraps waveform + handle in `VStack(spacing: 0)` with shared `.padding(.horizontal, 8)` (post-merge fix `b59c87d` lifted padding above VStack to align flush edges); 5 new drag-math tests in `WaveformVerticalZoomControllerTests.swift` (10 total). **Superseded by PR #74's hover-revealed rails** — the bottom-edge handle was axis-perpendicular; the right-edge vertical rail is the corrected design.
- [x] [#73](https://github.com/chienchuanw/only-cue/issues/73) → PR [#74](https://github.com/chienchuanw/only-cue/pull/74) — hover-revealed waveform zoom rails (vertical right edge + horizontal bottom); new `WaveformZoomController.applyDrag(...)` mirrors PR #69's vertical version through `setZoom(_:anchorFraction:viewportWidth:scrollOffset:)` to preserve scroll-anchor; new `WaveformZoomRail` view parameterized by `axis: Axis` enum (`.vertical` / `.horizontal`) with hover-aware fill, `NSCursor.resizeUpDown`/`resizeLeftRight`, magnifier-glyph badge with live zoom level, double-click reset; `WaveformContainer.loaded(peaks:)` switched to `ZStack(alignment: .bottomTrailing)` overlay with hover state + 1.5s first-launch hint; rail wiring extracted to new `WaveformContainer+ZoomRails.swift` extension to keep struct body under SwiftLint's 250-line cap; 6 new horizontal-drag tests in `WaveformZoomRailHorizontalDragTests.swift` (195 total). **Vertical-zoom bullet COMPLETE end-to-end — keyboard (PR #67) + axis-aligned hover-rail (PR #74).** Senior review filed three non-blocking polish observations as follow-up [#77](https://github.com/chienchuanw/only-cue/issues/77).
- [x] [#77](https://github.com/chienchuanw/only-cue/issues/77) — chore: polish hover-zoom-rails per PR #74 senior review (non-cancellable hint timer → `.task`-based, session-scoped `hasShownFirstLaunchHint`, comment on unused `0.5` anchor literal). **Status:** open, ready for autonomous shipping when next bypass-mode session starts.

### Stand-alone UX papercut leaves

- [x] [#78](https://github.com/chienchuanw/only-cue/issues/78) → PR [#79](https://github.com/chienchuanw/only-cue/pull/79) — cue inspector commits drafts on outside-click; window-scoped `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` resigns the first responder when the click lands outside the active text field's frame, which fires the existing `commitOnFocusLeave` machinery in `CueInspectorView`; pure-logic `FirstResponderResign.shouldResign(...)` predicate split out for unit tests (4 new); `FirstResponderResignOnOutsideClick` ViewModifier + private file-scope `FirstResponderResignMonitor` `NSViewRepresentable` (split to keep `Coordinator` within SwiftLint's nesting cap of 1); applied once at `DocumentView` root so the monitor is window-scoped (not view-scoped, which would leak on every cue selection rebuild); merged clean with no review feedback. **8th consecutive bypass-mode shipment, second against a user-pre-authored spec + plan.**

- [x] [#76](https://github.com/chienchuanw/only-cue/issues/76) → PR [#80](https://github.com/chienchuanw/only-cue/pull/80) — File > Import Media… menu entry; new `Notification.Name.importMediaRequested` posted by `CommandGroup(after: .newItem)` in `AppCommands` and observed by `DocumentView.onReceive` (receiver owns the name, mirroring `WaveformContainer`'s pattern); ⌘O moves from the in-app button to the menu item (sole owner, no duplicate-shortcut ambiguity); `Label("Import Media…", systemImage: "square.and.arrow.down")` future-proofs the icon for any surface that renders it; merged clean with no review feedback. **9th consecutive bypass-mode shipment, 3rd against user-pre-authored spec + plan.**
- [ ] Waveform gain control — likely redundant with the hover-zoom rails shipped in PR #74 (the held-zoom state already provides persistent visualization). Candidate to close as won't-fix unless user has different intent.
- [ ] Multi-select model (Cmd-click + Shift-click) — gates `S` snap-to-playhead, `Option+arrow` nudge
- [ ] `S` snap selected cue(s) to playhead — depends on multi-select model
- [ ] `Option+←` / `Option+→` nudge selected cue(s) — depends on multi-select model
- [ ] tests — gesture handlers, selection state, batch-nudge undo

## Phase 3 milestone — Differentiator

Empty until Phase 2 ships. Three candidates from the roadmap: AI-assisted cueing, real-time collaboration, push/pull console integration. We pick one when Phase 2 is in user hands and we know which gap matters most.
