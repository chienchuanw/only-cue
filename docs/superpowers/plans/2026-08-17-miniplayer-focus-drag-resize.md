# Plan — Mini Player focus / drag / resize (#761)

Spec: `docs/superpowers/specs/2026-08-17-miniplayer-focus-drag-resize-design.md`

Small, self-contained change to `MiniPlayerController` plus one new pure helper.
No `ProjectModel` schema change. TDD throughout: red test first, then green.

## Constants (single source of truth)

New `MiniPlayerSize` (pure): `min = 660`, `max = 1000`, `default = 660`,
`clamp(_:) -> CGFloat`.

## TDD steps (commit test red, then impl green)

1. **`MiniPlayerSize.clamp` unit** — `OnlyCueTests/MiniPlayerSizeTests.swift`
   - width < 660 → 660; width > 1000 → 1000; in-range unchanged; NaN/0 → 660.
   - constants are 660 / 1000 / 660.
   - Impl: add `OnlyCue/UI/MiniPlayerSize.swift`.

2. **`MiniPlayerController` panel-config regression guards** —
   `OnlyCueTests/MiniPlayerControllerConfigTests.swift`
   Expose the configured panel for assertions (a test seam: either a factory
   `MiniPlayerController.makePanelForTesting()` or assert via a created panel).
   - key-capable: `panel.canBecomeKey == true`; style mask does NOT contain
     `.nonactivatingPanel`.
   - `panel.isMovableByWindowBackground == false`.
   - style mask contains `.resizable`.
   - `panel.minSize.width == 660`, `panel.maxSize.width == 1000`,
     `panel.minSize.height == panel.maxSize.height` (height locked, > 0).
   - still `isFloatingPanel == true`, `level == .floating`.
   - Impl in `MiniPlayerController.makePanel`:
     - style mask `[.titled, .closable, .utilityWindow, .resizable]` (drop
       `.nonactivatingPanel`); if a subclass is needed for `canBecomeKey`, add a
       minimal `NSPanel` subclass.
     - `isMovableByWindowBackground = false`.
     - set `minSize` / `maxSize` from `MiniPlayerSize` + fixed content height.
     - remove `rootView.frame(width:)`; host width-flexible; open width = 660,
       clamp restored autosave width into range.

3. **`MiniPlaybackGate` truth table** — already covered; re-run the existing
   `MiniPlaybackGateTests` to prove no regression (no code change expected).

4. **Reflow verify (no structural change)** — confirm `MiniPlayerView.body` renders
   at 660 and 1000 without overlap (SwiftUI preview / existing snapshot if any).
   Matches Figma `607:3185`.

## Manual smoke test (AppKit glue, not unit-testable)

- Collapse to Mini / click the panel → Space toggles playback, ↑/↓ step cues,
  ←/→ seek, GO (Show), `[` `]` `\` rate.
- With main window open + key, its shortcuts still win (gate yields).
- Drag scrub knob → seeks; window moves only by title bar.
- Resize width 660↔1000: title absorbs extra width, current cue name always shown;
  reopen app → width restored clamped.
- Panel still floats above other apps.

## Out of scope / guards

- No global hotkeys. No vertical resize. No schema bump. Deployment target ≥ 14.0.
- `swiftlint` clean; `TokenConformanceTests` still green (main-window rule
  unaffected — Mini Player already uses `DS.*`).
