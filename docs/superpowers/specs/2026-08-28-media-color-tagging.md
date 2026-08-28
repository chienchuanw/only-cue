# Media color tagging in the media panel

**Status:** approved 2026-08-28 — Figma design signed off
**Figma:** `NhH2957iKQ8b581x3gI3Wk` — component set `77:43` (`ItemRowView`, with
the `Show Color` boolean property), screens `318:1238` / `318:1228`
**Touches:** `OnlyCue/Document/MediaItem.swift`, `ProjectModel` schema v21 → v22,
`OnlyCue/Commands/CueCommands+Media.swift`, `OnlyCue/UI/ItemListPane.swift`,
`OnlyCue/UI/ItemRowView.swift`
**Prior art:** `CuePointType.colorHex` + `CuePointType+DefaultPalette` (the color
pattern being reused verbatim), `CueRowView` type stripe, #752 (the macOS
`Menu` checkmark trap)

## Goal

Let the user mark a media item with one of eight colors, so a long media list
can be scanned and visually grouped at a glance.

## Non-goals

Each was raised and deliberately declined during the design interview.

- **Named tags.** No `MediaTag` type, no name, no management sheet. A color is
  just a color; what it *means* lives in the user's head.
- **Filtering, sorting, grouping by color.** Purely visual in v1.
- **Keyboard shortcuts.** Number keys already drive `CuePointType.hotkey`;
  claiming them for colors needs a focus-routing audit that is out of scope.
- **Multi-select batch coloring.** `ItemListPane` is single-select today
  (`Binding<MediaItem.ID?>`); adding multi-select is its own change.
- **Anything in the MA2 push or plugin export.** Those formats carry no color
  concept and must not be polluted with one.
- **Any surface outside the media list** — not Show Mode, not the transport bar.

## Decisions

| # | Question | Decision |
| - | -------- | -------- |
| 1 | Color or named tag? | **Plain color.** `colorHex: String?` directly on `MediaItem`. |
| 2 | Which colors? | **The existing 8-color palette**, `CuePointType.defaultPalette`, reused as-is. |
| 3 | How is it shown? | **Leading color stripe** on the row, same idiom as `CueRowView`. |
| 4 | How is it set? | **Context menu submenu only.** No edit-sheet field. |
| 5 | Scope | **Purely visual, media list only.** |
| 6 | Unmarked rows | **Blank** — deliberately *unlike* `CueRowView`, which falls back to `DS.Color.border`. |

Decision 6 is the one intentional deviation from precedent, so the reasoning is
recorded rather than left to be rediscovered: in the cue list, *having a type*
is the normal state, so a fallback stripe keeps rows aligned. In the media list,
*having a color* is the exception — most items will never be tagged. Drawing a
grey stripe on every untagged row would make the marked ones stop standing out,
which is the entire point of the feature.

## Data model

```swift
// MediaItem.swift
var colorHex: String?   // canonical "#RRGGBB", or nil for untagged
```

Codable wiring follows the file's existing shape exactly: add the case to
`CodingKeys`, `decodeIfPresent` in `init(from:)`, `encodeIfPresent` in
`encode(to:)`.

Validation: the setter accepts only values from the palette, so no arbitrary or
malformed hex can reach the model. `Color(hex:)` already returns `nil` on a bad
string, so a hand-edited `.cuelist` degrades to "untagged" rather than crashing.

### Migration

`ProjectModel.currentSchemaVersion` 21 → 22, plus
`ProjectModel+MigrationV21.swift` with a `LegacyV21` struct, mirroring
`ProjectModel+MigrationV20.swift`. Add `case 21:` to the dispatcher switch in
`ProjectModel+Migration.swift`.

Because `colorHex` is optional with a `nil` default, the migration is a pure
re-wrap — a v21 document loads with every item untagged. This matches how
`rememberedLTC` was added in v19 → v20.

## Command

New single-field command in `CueCommands+Media.swift`, following the
`setLTCMuted` pattern in `CueCommands+Timecode.swift` verbatim (index guard,
no-op guard, undo grouping, `setActionName`):

```swift
static func setMediaColor(
    itemID: MediaItem.ID,
    colorHex: String?,
    document: CueListDocument,
    undoManager: UndoManager?
)
```

Undo action name: `"Set Color"` when assigning, `"Clear Color"` when passing
`nil`. `MediaItemEdit` is **not** extended — the edit sheet has no color field,
so adding one there would be dead surface.

## UI

### Row stripe — `ItemRowView.swift`

A leading `Rectangle` overlay, width from a new
`ItemRowMetrics.colorStripeWidth: CGFloat = 5` (matching
`CueListLayout.typeStripeWidth`, but declared locally — `CueListLayout` belongs
to the cue pane and reaching across panes for a constant would couple them).

Rendered only when `item.colorHex` resolves to a color; otherwise nothing is
drawn. The stripe sits at the leading edge, outside the selection pill, so
selection and tagging stay visually separable.

The row content is inset by a second new metric:

```swift
/// Stripe + breathing room, so the colour never crowds the kind icon.
static let colorGutter: CGFloat = colorStripeWidth + DS.Space.sm   // 13
```

Reserved on **every** row, tagged or not — mirroring `CueListLayout
.rowLeadingGutter`, which the cue list also reserves unconditionally. If only
tagged rows were inset, the whole row's text would jump horizontally on every
tag/untag. Accepted cost: the sidebar is 248 pt wide and names already
tail-truncate, so they now truncate ~5 pt earlier. Verified in Figma
(`77:43`, `paddingLeft` 8 → 13; screens `318:1238` / `318:1228`).

No `DS` token is required for the fill: the color is document data, not chrome,
exactly like `CueRowView`'s stripe. `TokenConformanceTests` is satisfied because
no raw literal is introduced.

### Context menu — `ItemListPane.swift`

A `Color` submenu inserted after "Show in Finder", with the 8 palette swatches
plus a "None" entry.

**Implementation constraint:** the submenu must be built with an inline
`Picker`, not `Button` + `Label(systemImage:)`. On macOS, SwiftUI silently drops
the checkmark in the latter form — this cost a full debugging cycle in #752 and
must not be rediscovered.

### Accessibility

Non-negotiable per the global rules, and the reason the colors need names at
all despite decision 1:

- Each swatch carries a text label — Red, Orange, Yellow, Green, Teal, Blue,
  Purple, Pink — so the menu is operable and announceable without color vision.
- The stripe gets `.accessibilityIdentifier("itemRowSwatch-\(item.id)")`,
  mirroring `cueRowSwatch-\(cue.id)`, and an accessibility label naming the
  color so the tag is perceivable to VoiceOver rather than color-only.

## Tests (TDD — red first)

**Unit** — new `CueCommandsSetMediaColorTests.swift`, modelled on
`CueCommandsUpdateMediaItemTests.swift`:

1. Sets `colorHex` on the target item.
2. Leaves other items untouched.
3. Is a single undo step; undo restores the previous value.
4. Unknown item ID is a no-op.
5. Setting the already-current color is a no-op (no undo registered).
6. `nil` clears an existing color.
7. A non-palette hex is rejected.

**Migration** — v21 fixture decodes at v22 with every item untagged; a
round-trip of a tagged document preserves the hex.

**UI** — extend the media-panel UI tests: assign a color via the context menu
and assert `itemRowSwatch-<id>` exists; assert it is absent for an untagged row.

## Acceptance criteria

```gherkin
Given a media item with no color
When I right-click it and choose Color > Green
Then the row shows a green stripe at its leading edge
And the change is undoable as a single step

Given a media item colored green
When I right-click it and choose Color > None
Then the stripe disappears

Given a project saved with colored media
When I reopen it
Then the colors are still there

Given a .cuelist written at schema v21
When I open it
Then it loads at v22 with every item untagged and nothing is lost
```

## Accepted risk

With eight unnamed colors and no filtering, the feature's value rests entirely
on the user remembering what each color means. That was chosen knowingly over
named tags. If it turns out not to hold, the upgrade path is additive — a
`MediaTag` type with `MediaItem.tagID`, migrating existing `colorHex` values
into generated tags — and nothing in this design blocks it.

**Shared palette implies a relationship that does not exist.** A media item and
a cue type can now wear the same orange while meaning nothing to each other.
Reviewed against the full Cue Mode screen and accepted: the two lists sit at
opposite edges of the window with the waveform between them; cue stripes appear
on *every* row while media stripes are sparse; and cue colors have a second home
on the timeline markers, which media colors never get. Minting a second 8-color
palette was rejected — in one dark UI it would land on near-duplicates of the
first, and a *subtle* color difference implies kinship more strongly than an
identical one.

## Housekeeping found during design

- `CLAUDE.md` said the schema was "currently at v19" and `docs/data-model.md`
  was stale at v20 with the v20 → v21 migration entry missing. Both corrected
  separately from this feature.
- Figma variable `cue/indigo` is `#6155F5`, but `CuePointType.defaultPalette`
  slot 5 is `#4ECDC4` (teal). The other seven match. Pre-existing Figma↔code
  drift, tracked in #783; deliberately untouched here.
