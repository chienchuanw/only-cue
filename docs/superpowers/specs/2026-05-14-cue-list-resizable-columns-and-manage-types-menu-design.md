# Cue List — Resizable Columns & "Manage Types" Menu Relocation

**Date:** 2026-05-14
**Status:** Approved (brainstorming)
**Scope:** Two small, independent UX changes to the right-side `CueListPane`.

## Motivation

The cue list's column widths are hard-coded (`CueListLayout.timeColumnWidth = 96`, `numberColumnWidth = 56`). Lighting designers working with longer cue numbers or tighter pane widths cannot adapt the layout to their content. Additionally, the `Manage Types…` button sits at the bottom of the cue inspector (`CueInspectorView.swift:38`) — a per-cue editing surface — even though it is a project-wide settings action shown identically regardless of cue selection. It belongs in the menu bar alongside other management surfaces (Timecode Settings, OSC Monitor).

## A. Resizable cue list columns

### Scope

The cue list's **Time** and **Number** columns get drag handles in the header row. The **Name** column stays flexible (fills the remaining pane width). The inspector form below the cue list is unchanged.

### Storage

Widths persist globally via `@AppStorage` (a user preference, not a per-document property — no schema bump):

| Key                          | Default | Min | Max |
|------------------------------|---------|-----|-----|
| `cueList.timeColumnWidth`    | 96      | 64  | 180 |
| `cueList.numberColumnWidth`  | 56      | 40  | 120 |

Clamping happens on write. Out-of-range stored values (e.g. from a manually edited prefs file) are clamped on read.

### Interaction

- Hover the right edge of the Time or Number header cell → `NSCursor.resizeLeftRight`.
- Drag updates the stored width live; release commits. No transient/committed distinction — every drag delta writes through.
- No double-click-to-reset in v1 (YAGNI; can be added later if requested).
- No keyboard or accessibility resize affordance in v1; widths are mouse-only.

### Wiring

Today `CueListPane` (header) and `CueRowView` both read `CueListLayout.timeColumnWidth` / `numberColumnWidth` directly. Introduce a lightweight value type that both consume so the header and every row stay aligned during drag:

```swift
struct CueListColumnWidths {
    var time: CGFloat
    var number: CGFloat

    static let timeRange: ClosedRange<CGFloat> = 64...180
    static let numberRange: ClosedRange<CGFloat> = 40...120

    static let defaults = CueListColumnWidths(time: 96, number: 56)
}
```

A `CueListColumnWidthsStore` (`ObservableObject` backed by `@AppStorage`, or a small wrapper around `UserDefaults`) is owned by `CueListPane` and passed to `CueRowView` via parameter (preferred) or environment.

`CueListLayout` keeps `rowHorizontalSpacing` and `rowTintOpacity` but **loses** `timeColumnWidth` and `numberColumnWidth` — every read site is replaced.

### Files touched

- `OnlyCue/UI/CueListPane.swift` — drop static widths; own the store; add header drag handles.
- `OnlyCue/UI/CueRowView.swift` — read widths from the passed store instead of `CueListLayout`.
- New: `OnlyCue/UI/CueListColumnWidths.swift` — value type, store, clamp helpers.

### Tests

- Unit: `CueListColumnWidths` clamps on write and on read; defaults round-trip; out-of-range stored values normalize.
- UI: drag the Number column header divider; assert the corresponding `CueRowView`'s number-column frame width matches; relaunch (simulate) preserves width.

## B. Move "Manage Types…" to the Tools menu

### Placement

**Tools menu**, inserted as the first item (above Edit Note Overlay Appearance). Rationale: it groups with the other management/settings sheets already there. Edit menu is reserved for action verbs; a new top-level "Cues" menu for one item is premature.

### Changes

1. **`OnlyCue/App/AppCommands.swift`** — in the `CommandMenu("Tools")` block, add at the top:
   ```swift
   Button("Manage Types…") {
       NotificationCenter.default.post(name: .manageTypesRequested, object: nil)
   }
   Divider()
   ```
2. **`OnlyCue/UI/DocumentView.swift`** — add `@State private var showManageTypes = false`; observe `.manageTypesRequested` and toggle the state; attach `.sheet(isPresented: $showManageTypes) { TypeManagementSheet(document: document) }`.
3. **`OnlyCue/UI/CueInspectorView.swift`** — delete:
   - the `Button("Manage Types…")` and its preceding `Divider()` (lines ~36–40),
   - the `showTypesSheet` `@State`,
   - the trailing `.sheet(isPresented: $showTypesSheet) { TypeManagementSheet(document: document) }`.
   The inspector becomes purely cue-field editing.
4. **Notification name** — add `static let manageTypesRequested = Notification.Name("OnlyCue.manageTypesRequested")` to the existing extension at the bottom of `DocumentView.swift`.
5. **Accessibility identifier** — the menu item carries `accessibilityIdentifier("manageTypesButton")` so existing UI tests that find it by identifier keep working. (If macOS menu items don't honor `accessibilityIdentifier` reliably, fall back to renaming tests to drive the menu by title — note this in the leaf.)

### Out of scope

- No keyboard shortcut for Manage Types (rare action).
- No icon.
- No reordering of other Tools entries.

## Verification

- Drag Time header divider → Time column resizes live; rows stay aligned with header; width persists after quit/relaunch.
- Drag Number header divider → same.
- Widths clamp at min and max; no visual glitches at bounds.
- Tools → Manage Types… opens the sheet from any selection state (including no cue selected, where the inspector was previously hidden).
- Cue inspector no longer shows the Manage Types button or the divider above it.
- UI tests pass; accessibility identifier `manageTypesButton` continues to resolve to the new menu item (or tests updated to drive by menu title).

## Non-goals

- Per-document column widths (would require schema bump; not requested).
- Resizable Name column (it absorbs remaining width by design).
- Reset-to-defaults gesture.
- Refactoring `CueInspectorView` beyond the two-button deletion.
