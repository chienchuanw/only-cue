# Remove the blue system selection highlight in the cue/media lists (#679)

Status: approved
Issue: #679

## Problem

Selecting a cue in `CueListPane` or a media item in `ItemListPane` shows the
macOS dark-blue / reverse-video system selection highlight, clashing with the
design system. Both panes use `List(selection:)`; the backing `NSTableView`
paints its emphasized blue highlight over the custom `.listRowBackground`
(`CueRowFill` / `ItemRowFill`) each pane already provides. SwiftUI has no
official API to recolor or disable that highlight.

## Decision (grilled)

- **Approach:** AppKit introspection, *keeping* `List(selection:)` so keyboard
  navigation, shift/cmd multi-select and the focus ring all stay. Applies to
  both panes.
- **Visual:** once the blue is gone, show the design system's existing subtle
  treatment (selected cue row → cue-type tint; selected media row → achromatic
  rounded pill). No new selection style.

## Design

- New `OnlyCue/UI/TableSelectionHighlightStyler.swift`:
  - Pure `disableSystemHighlight(from: NSView) -> NSTableView?` — walks up the
    superview chain to the nearest enclosing `NSTableView`, sets
    `selectionHighlightStyle = .none`, returns it (nil if none). Unit-testable.
  - `NSViewRepresentable` probe + `View.plainListSelectionHighlight()` that
    hosts a zero-size probe via `.background`; `makeNSView` and `updateNSView`
    both re-apply (accepted introspection fragility — re-applied on updates so a
    SwiftUI table rebuild can't silently restore the blue).
- `CueListPane` and `ItemListPane` rows each gain `.plainListSelectionHighlight()`.
- Drawing only — selection state, keyboard nav, multi-select, context menu and
  drag-reorder are untouched.

Walking *up* from a per-row probe targets each list's own `NSTableView` (both
panes live in one window, so a window-wide search could style the wrong table).

## What stays the same

- `ProjectModel` schema (none), App Sandbox (none, ADR-007), macOS 14.0 floor
  (ADR-001), version number (release decided separately).
- `List(selection:)` behavior and the `CueRowFill` / `ItemRowFill` precedence
  logic and their unit tests.

## Test plan (TDD)

- **Unit** (`TableSelectionHighlightStylerTests`): build a synthetic
  `NSTableView → rowView → probe` tree; `disableSystemHighlight(from: probe)`
  sets the table's `selectionHighlightStyle` to `.none` and returns that table;
  a tree with no table returns nil and changes nothing.
- **UITest**: select a row and assert it is still marked selected (keyboard nav
  intact); attach a screenshot for visual confirmation that no blue shows.
