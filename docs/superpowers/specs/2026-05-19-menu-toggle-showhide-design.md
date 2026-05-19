# Menu Toggle Show/Hide Verb — Design

Date: 2026-05-19
Status: Approved
Scope: Convert checkable menu `Toggle`s to state-flipping `Button`s to remove the
native state-column indentation. No behavior change.

## Problem

In `OnlyCue/App/AppCommands.swift`, four menu items are SwiftUI `Toggle`s:

- View menu (`CommandGroup(after: .sidebar)`): `Show Notes Overlay`,
  `Show Timeline Breakdown`, `Show Tempo Grid`.
- Playback menu (`CommandMenu("Playback")`): `Pause at Each Cue`.

A SwiftUI `Toggle` inside `Commands` renders as a native *checkable*
`NSMenuItem`. AppKit reserves a leading state-column (the checkmark gutter) for
checkable items, so these toggles sit visually indented relative to the plain
`Button` items in the same menus (e.g. `Zoom In Horizontally`,
`Speed Up`). This is standard AppKit behavior, not a bug, but the user wants
the items left-aligned with the surrounding buttons.

## Goals

- Remove the state-column indentation so these items align with the other
  menu buttons.
- Preserve the on/off affordance with a macOS-idiomatic state-flipping verb
  (the Show/Hide pattern used by system menus, e.g. Show/Hide Sidebar).
- Zero behavior change: same `@AppStorage` keys, same keyboard shortcuts,
  same effect.

## Non-Goals

- No change to `@AppStorage` keys, `Keymap`, `KeymapStore`, `KeymapAction`, or
  `NotificationCenter` names.
- No change to any other menu item, divider, or structure.
- No new on-screen UI; this is menu-only.

## Change

In `OnlyCue/App/AppCommands.swift`, replace each `Toggle` with a `Button`
whose title is derived from the bound `@AppStorage` property and whose action
flips that property. Keyboard shortcuts are kept verbatim.

View menu (`CommandGroup(after: .sidebar)`):

```swift
Button(showNotesOverlay ? "Hide Notes Overlay" : "Show Notes Overlay") {
    showNotesOverlay.toggle()
}
.keyboardShortcut(shortcut(.toggleNotesOverlay))

Button(showTimelineBreakdown ? "Hide Timeline Breakdown" : "Show Timeline Breakdown") {
    showTimelineBreakdown.toggle()
}
.keyboardShortcut(shortcut(.toggleTimelineBreakdown))

Button(showTempoGrid ? "Hide Tempo Grid" : "Show Tempo Grid") {
    showTempoGrid.toggle()
}
.keyboardShortcut(shortcut(.toggleTempoGrid))
```

Playback menu (`CommandMenu("Playback")`):

```swift
Button(pauseAtEachCue ? "Don't Pause at Each Cue" : "Pause at Each Cue") {
    pauseAtEachCue.toggle()
}
.keyboardShortcut(shortcut(.togglePauseAtEachCue))
```

`Pause at Each Cue` is a behavior mode, not a visibility toggle, so the
Show/Hide verb does not fit; the off/on labels are
`Pause at Each Cue` / `Don't Pause at Each Cue` (parallel to the macOS
"Don't Save" idiom). The four `@AppStorage` property declarations at the top
of `AppCommands` are unchanged; `.toggle()` writes through the same
`@AppStorage`-backed property the `Toggle` previously bound with `$`.

## Test impact

No frozen-label breakage (verified via grep over `OnlyCueUITests/` and
`OnlyCueTests/`):

- `OnlyCueUITests/TempoGridOverlayScreenshotTests.swift` triggers the tempo
  grid via the keyboard shortcut `⇧⌘G` (`app.typeKey("g", …)`), not the menu
  title. Only code comments mention "Show Tempo Grid".
- `OnlyCueUITests/MenuBarReorganizationUITests.swift` line 33
  (`app.menuItems["Pause at Each Cue"].waitForExistence`) and line 54
  (`XCTAssertFalse(viewMenu.menuItems["Pause at Each Cue"].exists)`) both
  remain valid: the seeded launch state has all four flags **off**, so the
  off-state labels are exactly `Pause at Each Cue` (present under Playback,
  absent from View) — unchanged from today.

## Testing

Extend `OnlyCueUITests/MenuBarReorganizationUITests.swift` (TDD: assertions
added first, fail against the current `Toggle` titles where they differ, then
the conversion turns them green):

- Open the View dropdown; assert `Show Notes Overlay`,
  `Show Timeline Breakdown`, `Show Tempo Grid` exist (the default off-state
  titles — identical strings to today, but now plain buttons).
- Open the Playback menu; assert `Pause at Each Cue` exists in the off state.
- Click `Show Tempo Grid`, reopen the View dropdown, assert the item now reads
  `Hide Tempo Grid` (proves the state-flipping verb and that the action still
  toggles the persisted flag).

Local UITest execution is blocked by a macOS TCC automation-mode timeout on
the dev machine; the local gate is build + SwiftLint + the `OnlyCueTests`
unit suite, and UITests are gated on CI (CI runs the full `xcodebuild test`
including `OnlyCueUITests`).

## Risks

Low. One declarative file, four item conversions, no model/command/keymap/
notification surface touched. The only observable changes are the removed
indentation and the state-dependent verb in the title.
