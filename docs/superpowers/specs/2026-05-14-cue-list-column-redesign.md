# Cue list column redesign

**Status:** approved
**Date:** 2026-05-14
**Scope:** `OnlyCue/UI/CueListPane.swift`, `OnlyCue/UI/CueRowView.swift`, and the
View-menu command that toggles the BPM column. No data-model, document-schema,
or `CueCommands` changes.

## Motivation

The cue list above the inspector has accumulated UI it does not need:

- A search field that filters by name/notes. Real cue lists are short enough
  that scroll + keyboard navigation already work; the filter adds noise.
- A leading 1, 2, 3… position-index column that duplicates information the
  user already perceives from row order.
- A small circular color swatch that competes with the row's other content for
  the same visual job: "which cue is this."
- A BPM column hidden behind a hidden toggle. The inspector exposes BPM
  directly; the column is rarely on and its absence is not missed.
- No column headers, so a reader has to infer what each cell means.

This spec consolidates the row into the three pieces of information the user
actually scans for — **Time, Cue #, Cue Name** — and moves cue color from a
swatch into a tinted row background that ties color to row identity.

## Goals

1. Render every row as `Time | Cue # | Cue Name`, in that left-to-right order.
2. Show a non-interactive column header row above the list.
3. Replace the circular color swatch with a tinted row background derived from
   the cue's resolved color.
4. Remove the search field, the leading position-index column, and the BPM
   column (including its `@AppStorage` toggle and View-menu command).

## Non-goals

- No changes to the inspector pane (`CueInspectorView`).
- No changes to selection, snap, nudge, duplicate, delete, or keyboard
  shortcuts.
- No sortable / resizable / draggable column headers — headers are labels
  only.
- No removal of the `CueColorSwatch` view type itself; it remains in use
  inside the inspector and preview surfaces.

## Detailed design

### Column layout

A single set of width constants is shared by the header row and `CueRowView`:

| Column   | Width        | Alignment | Editable          |
|----------|--------------|-----------|-------------------|
| Time     | 96pt fixed   | leading   | no (snap / nudge) |
| Cue #    | 56pt fixed   | leading   | yes (double-tap)  |
| Cue Name | flexible     | leading   | yes (double-tap)  |

Time uses `.system(.body, design: .monospaced)` so digit columns align. Cue #
keeps its existing monospaced rendering and `FadeTime.formatNumber`
formatting. Cue Name keeps `.lineLimit(1)` + `.truncationMode(.tail)`.

### Header row

A `HStack` with the same three columns and widths, rendered above the `List`,
separated by a `Divider()`. Header labels: "Time", "Cue #", "Name". Styling:
`.font(.caption)`, `.foregroundStyle(.secondary)`, `.padding(.horizontal, 8)`,
`.padding(.vertical, 6)`. Accessibility identifier: `cueListHeader`.

### Row background tint

`CueRowView` is rendered inside a `List` row. The row applies
`.listRowBackground(tint)` where:

```
tint = Color(hex: resolvedColorHex).opacity(rowTintOpacity)  // when hex is non-nil
tint = Color.clear                                           // otherwise
```

`rowTintOpacity` is a single `private static let` constant on `CueRowView`
(initial value `0.18`) so we can tune after seeing it live without changing
call sites.

SwiftUI's `List` draws the selection accent above `listRowBackground`, so
selection visibility is preserved on every tint, including no-color rows.

### Removals

- `searchQuery` state, `searchField` view, `cueList`'s `VStack { searchField;
  Divider(); scrollableList }` wrapper, the `Self.filtered(_:by:)` helper, and
  the `visibleCues` computed property. The list iterates `cues` directly.
- The leading position-index `Text("\(index)")` cell in `CueRowView`.
  `CueRowView` no longer takes an `index:` parameter; accessibility ids that
  used `\(index)` switch to `\(cue.id)`.
- The `CueColorSwatch(...)` call in `CueRowView`.
- The `@AppStorage("showBPMColumn")` property and its BPM cell in
  `CueRowView`.
- The View-menu command that toggled `showBPMColumn`. The `@AppStorage` key
  itself is left in place (no migration needed; SwiftUI ignores unknown keys).

### Swipe-to-delete and offsets

`deleteAtOffsets(_:)` currently indexes into `visibleCues`. With the filter
removed, it indexes into `cues` directly. Behavior is unchanged for the user.

## Tests

- **Remove:** `OnlyCueTests/CueListFilterTests.swift` (filter helper is gone).
- **Remove:** any `CueRowView` test that asserts BPM column visibility.
- **Update:** existing `CueListPane` UI tests that look up
  `cueListSearchField` — drop those assertions.
- **Add:** a row-layout test for `CueRowView` that asserts:
  - column order is Time, Cue #, Name (left to right),
  - no color swatch view is present,
  - no leading position-index cell is present.
- **Add:** a `CueListPane` test that asserts a header row with id
  `cueListHeader` renders and that `cueListSearchField` does not.
- **Verify still green:** `CueInspectorTempoSnapshotTests`,
  `CueInspectorCommitTests`, `CueCommands*Tests`.

## Risks and trade-offs

- **Losing the BPM column.** BPM remains visible in the inspector and on the
  derived tempo grid. If at-a-glance BPM scanning becomes important again we
  can re-introduce it as a real column rather than a hidden toggle.
- **Losing search.** If cue counts grow beyond ~50 we may want it back. The
  cost of reintroducing the filter helper later is low (~30 lines).
- **Tint opacity choice.** 18% reads well across our existing palette in both
  light and dark mode; the constant makes adjustment trivial.

## Open questions

None. Approved in brainstorm.
