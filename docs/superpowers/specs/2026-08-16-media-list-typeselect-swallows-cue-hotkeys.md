# Media list type-select swallows digit cue hotkeys

- **Date:** 2026-08-16
- **Kind:** bug
- **Status:** approved (design agreed with user)
- **Subsystem:** `UI/` — media sidebar (`ItemListPane`), keyboard shortcut routing

## Problem

Pressing a digit (`0`–`9`) is supposed to create a cue of the user-configured
type at the playhead (`DocumentView+Shortcuts.swift` → `triggerHotkey`). In
practice, pressing e.g. `1` sometimes **selects/jumps to a media item** in the
left sidebar instead of creating a cue, and **no cue is created**.

### Root cause (confirmed against code)

- The media sidebar is a SwiftUI `List(selection:)` backed by AppKit
  `NSTableView` (`ItemListPane.swift:104`).
- That `NSTableView` is effectively the window's **persistent first responder**:
  clicking the waveform uses gestures (`WaveformSeekSurface.swift`) that do **not**
  change first responder, and nothing hands focus to the main pane. So the table
  holds keyboard focus regardless of where the user clicks.
- `NSTableView` has **built-in type-select** (typing jumps to the row whose label
  starts with the typed character). It consumes the key **before** it can reach
  the window-level `.keyboardShortcut` digit buttons that create cues.
- Result asymmetry the user observed:
  - Media are named with leading digits (`1_intro`, …) → `1` matches → type-select
    jumps + swallows the key → cue hotkey never fires.
  - `M` is bound to `.addCue` (`Keymap.swift:117`); no media starts with `M` →
    type-select finds no match → key falls through → cue **is** created.
- Independent of click location, because the table is always first responder.
- There is **no** intentional "select media by number" feature; the jump is purely
  a side effect of `NSTableView` type-select.

## Goal

Digit cue hotkeys (and `M`/any cue shortcut) always create a cue at the playhead,
regardless of prior interaction with the media list. The media list must not
consume typed characters for type-select.

## Non-goals

- No keyboard navigation of the media list is added or preserved. Media selection
  stays mouse-only (it already is — the list has no arrow-key nav). The user has
  explicitly confirmed they do not want type-select.
- No change to cue-type hotkey configuration (`manage types`), which remains
  digits `0`–`9`.

## Approach

Extend the existing AppKit-introspection seam used for #679
(`TableSelectionHighlightStyler` / the zero-size probe hosted behind a list row)
to also disable type-select on the media list's backing `NSTableView`.

Preferred mechanism (to be confirmed by running the app in the TDD loop):

1. **`NSControl.refusesFirstResponder = true`** on the backing `NSTableView`.
   The table never becomes first responder → its `keyDown` (and thus type-select)
   never fires → digit/letter keys fall through to the window-level cue shortcuts.
   Mouse-click row selection is unaffected (click selection does not require first
   responder). Trade-off: loses arrow-key row navigation (not used).

If (1) proves to break mouse selection or the `.onMove`/`.onDelete` affordances at
runtime, fall back to:

2. Suppressing type-select via the table delegate
   (`tableView(_:typeSelectStringForTableColumn:row:)` → `nil`) — riskier because
   SwiftUI owns the coordinator/delegate; only if (1) fails.

The probe re-applies on `viewDidMoveToWindow` / `viewDidMoveToSuperview` and on
every `updateNSView`, mirroring the existing highlight styler, so a table rebuild
can't silently restore type-select.

Scope the change to the **media list only** (walk *up* from the per-row probe as
the existing styler already does) so the cue list pane (`CueListPane`, which also
uses `.plainListSelectionHighlight()`) is not affected unless we decide it should
be — decide during implementation whether the cue list has the same latent bug.

## Acceptance criteria (Gherkin)

```gherkin
Scenario: Digit hotkey creates a cue even after touching the media list
  Given a project with media whose name begins with "1"
  And a cue type bound to hotkey "1"
  And the user has clicked a media item in the sidebar
  When the user presses "1"
  Then a cue of that type is created at the playhead
  And the media selection does not jump to the "1"-named item

Scenario: Media list no longer type-selects
  Given the media list has keyboard focus
  When the user types a character matching a media item's name prefix
  Then the selection does not change
```

## Test strategy

- **Unit / seam test:** a helper (extending `TableSelectionHighlightStyler`) that,
  given an `NSTableView`, applies the type-select-disabling change; assert the
  resulting state (e.g. `refusesFirstResponder == true`) on a synthesized table.
  This is the "see it red" test — write it before the helper exists.
- **Runtime-verify test:** mirror the recent `runtime-verify` pattern
  (e.g. the MiniPlayer panel-lifecycle test) to assert, against the real hosted
  list, that the backing table has type-select disabled after mount.
- Regression guard for #679: the system selection highlight stays disabled
  (both changes share the same probe).

## Risks / open questions

- `refusesFirstResponder` interaction with `.onDeleteCommand`/`deleteSelected`
  (⌫ to remove selected) — verify the Delete key path still works, since it may
  also rely on the table being first responder. If it breaks, that reopens the
  approach choice.
- Whether the cue list pane (`CueListPane.swift:310`) needs the same fix.
```
