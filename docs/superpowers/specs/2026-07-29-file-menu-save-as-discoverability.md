# File menu ordering — make `Save As…` findable

**Status:** approved (2026-07-29)
**Area:** `area:ui` — `OnlyCue/App/AppCommands.swift`

## Problem

`Save As…` is unfindable in OnlyCue's File menu. Users conclude the app has no
Save As feature.

It is not missing. `CueListDocument` is a SwiftUI `ReferenceFileDocument`, so
`DocumentGroup` supplies the whole standard document block — `Save`, `Save As…`,
`Duplicate`, `Rename…`, `Move To…`, `Revert To` — for free, and `Save As…` does
open a save sheet when clicked.

The problem is placement. `AppCommands` injects nine OnlyCue items at
`CommandGroup(after: .newItem)`, which lands them between `New` and `Open…` and
pushes every standard document command to the bottom of a 24-item menu. Menu
dump from `build/export/OnlyCue.app` (accessibility API, 2026-07-29):

```
New, ―, Import Media…, Export Cues…, Export Bundle…, Export PotPlayer Bookmarks…,
Send to grandMA2…, Export grandMA2 plugin…, ―, New from Template…,
Save Template As…, Load Template…, Open…, Open Recent, ―, Close, Close All,
Save, Save As…, Duplicate, Rename…, Move To…, Revert To, ―, Share
```

Two aggravating factors:

- `Save Template As…` appears eleven items *above* `Save As…`. Similar wording,
  different object (a `CuePointType` template, not the document).
- `Save As…` is bound to ⌥⇧⌘S (`Save` = ⌘S, `Duplicate` = ⇧⌘S — verified via
  `AXMenuItemCmdChar` / `AXMenuItemCmdModifiers`), so the keyboard offers no
  fallback route to discovery.

## Goal

Restore the macOS HIG File-menu order so `Save As…` sits where muscle memory
expects it, directly below `Save`, above the app-specific block.

## Non-goals

- No change to the save path, `CueListDocument`, or any file-writing code.
- **No `CommandGroup(replacing: .saveItem)`.** Reimplementing Save / Save As /
  Revert by hand recreates the split document ownership that caused #580
  (closing an edited document discarded changes with no prompt). The AppKit
  document machinery stays authoritative.
- No keyboard-shortcut changes, for the same reason — ⌥⇧⌘S is AppKit's.
- No rename of `Save Template As…`.
- No changes to the View / Cue / Playback / Tools menus.

## Target order

```
New
New from Template…
Open…  /  Open Recent
―
Close  /  Close All
Save  /  Save As…  /  Duplicate  /  Rename…  /  Move To…  /  Revert To
―
Share
―
Import Media…
Export Cues…  /  Export Bundle…  /  Export PotPlayer Bookmarks…
Send to grandMA2…  /  Export grandMA2 plugin…
―
Save Template As…  /  Load Template…
```

**Deviation from the original draft, confirmed by measurement.** The draft put
`Share` last. AppKit injects `Share` immediately after `Revert To`, and no
SwiftUI placement exists between the two, so the block necessarily lands below
it. `before: .printItem` resolves to the identical position but emits a doubled
separator, so `after: .saveItem` is the better anchor. `Share` sitting above the
app-specific block is cosmetic and does not affect the goal.

`New from Template…` splits out of the moving block into its own
`CommandGroup(after: .newItem)` — it is a document-creation verb and belongs
beside `New`. The remaining eight items move below the save block.

## Implementation risk

SwiftUI's `.saveItem` placement spans Save / Save As / Revert, while
`Duplicate`, `Rename…` and `Move To…` are injected by AppKit rather than
declared by SwiftUI. It is therefore not guaranteed that
`CommandGroup(after: .saveItem)` lands the block *after* `Revert To` rather
than in the middle of the standard group.

This is settled empirically, not by assumption: build, dump the File menu via
the accessibility API, compare against the target order. Fallback if it lands
wrong: `CommandGroup(before: .printItem)`.

## Acceptance criteria

```gherkin
Scenario: Save As… precedes the app-specific items
  Given a document window is open
  When I open the File menu
  Then "Save As…" appears above "Import Media…"

Scenario: New from Template… stays beside New
  Given a document window is open
  When I open the File menu
  Then "New from Template…" appears above "Open…"

Scenario: no item is lost in the move
  Given a document window is open
  When I open the File menu
  Then every pre-existing File-menu item is still present
```

- [ ] `Save As…` is positioned above `Import Media…` in the File menu.
- [ ] `New from Template…` is positioned above `Open…`.
- [ ] All nine pre-existing OnlyCue File items remain present and functional.
- [ ] Regression guard: an XCUITest in `MenuBarReorganizationUITests` asserts
      the `Save As…` / `Import Media…` ordering by comparing item frames.
- [ ] Before/after accessibility menu dumps recorded in the PR.
