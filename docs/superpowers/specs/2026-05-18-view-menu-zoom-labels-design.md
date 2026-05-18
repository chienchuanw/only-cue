# View Menu Zoom-Label Disambiguation — Design

Date: 2026-05-18
Status: Approved
Scope: Rename three horizontal-zoom menu items for clarity. No structural change.

## Problem

After the menu bar reorganization (#298 / PR #299), the `View` menu
(`CommandGroup(after: .sidebar)` in `OnlyCue/App/AppCommands.swift`) groups
waveform zoom into two divider-separated blocks:

- Horizontal: `Zoom In`, `Zoom Out`, `Actual Size`
- Vertical: `Zoom In Vertically`, `Zoom Out Vertically`, `Actual Vertical Size`

The vertical group is self-describing; the horizontal group is not. Read
top-to-bottom, "Zoom In" / "Zoom Out" / "Actual Size" give no hint they are the
horizontal counterparts, so the two blocks do not read as a parallel pair.
macOS menus offer no free-form indentation; the chosen fix is relabeling, not
submenus or section headers.

## Goals

- The horizontal zoom items state their axis, mirroring the vertical group so
  the two blocks read as parallel.
- Zero behavior change: shortcuts, notifications, dividers, and structure
  unchanged.

## Non-Goals

- No submenus or `Section` headers (flat list retained by user choice).
- No change to the vertical zoom items (already disambiguated).
- No change to the display toggles (`Show Notes Overlay`,
  `Show Timeline Breakdown`, `Show Tempo Grid`).
- No changes to `Keymap`/`KeymapStore`/`KeymapAction` or `NotificationCenter`
  names.

## Change

In `CommandGroup(after: .sidebar)`, rename three `Button` labels only:

| Old label    | New label              |
|--------------|------------------------|
| Zoom In      | Zoom In Horizontally   |
| Zoom Out     | Zoom Out Horizontally  |
| Actual Size  | Actual Horizontal Size |

`Actual Horizontal Size` is chosen over alternatives to mirror the existing
`Actual Vertical Size` exactly (same word order), so the two groups are
visually parallel.

Each button keeps its existing `.keyboardShortcut(shortcut(.waveformZoomIn))` /
`.waveformZoomOut` / `.waveformZoomReset` and its
`NotificationCenter.default.post(name: .waveformZoomIn / .waveformZoomOut /
.waveformZoomReset, …)`. Only the visible string changes.

## Test impact

`OnlyCueUITests/MenuBarReorganizationUITests.swift` line 49 contains a sanity
assertion:

```swift
XCTAssertTrue(viewMenu.menuItems["Zoom In"].exists)
```

This is the only test in the suite that references a zoom label by title
(verified via grep over `OnlyCueUITests/` and `OnlyCueTests/`). It must be
updated to `"Zoom In Horizontally"`.

## Testing

- **Update + extend `MenuBarReorganizationUITests`** (TDD, assertion changed
  first so it fails against the old label, then rename to green):
  - The View dropdown contains `Zoom In Horizontally`.
  - The View dropdown contains `Zoom In Vertically` (asserts both axis groups
    are clearly labeled and parallel).
  - The View dropdown no longer contains the bare `Zoom In`.
- Local UITest execution is blocked by a macOS TCC automation-mode timeout on
  the dev machine; build + SwiftLint + the `OnlyCueTests` unit suite are the
  local gate, UITests are gated on CI (CI runs the full `xcodebuild test`).

## Risks

Negligible. One declarative file, three string literals, plus one test
assertion update. No model, command, keymap, or notification surface touched.
