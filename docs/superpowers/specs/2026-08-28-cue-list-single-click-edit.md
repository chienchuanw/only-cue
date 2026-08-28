# Single-click inline editing in the cue list

**Status:** draft 2026-08-28 — awaiting approval
**Touches:** `OnlyCue/UI/CueRowView.swift`, `OnlyCue/UI/CueListPane.swift`,
new `OnlyCue/UI/CueRowTapIntent.swift`, `OnlyCueTests/`, `OnlyCueUITests/`
**Prior art:** `CueMarkersOverlay.swift:158-169` (modifier-aware tap — reused
verbatim as the selection idiom), `InlineEditFocus.swift` (the pure-function +
unit-test pattern this spec copies), #661 (blank empty name, inline Info),
#573 (`InlineEditGate` arrow-key gating)
**External reference:** CuePoints (third-party cue-sheet app) — the app this
interaction is modelled on. Behaviour was described by the user; its internals
were not inspected.

## Goal

Clicking a cue's `#`, `Name`, or `Info` cell puts the caret in that field
immediately, with no double-click. Editing a cue's text must not move the
playhead.

## The problem this creates, and the shape that solves it

A cue row is exactly three columns wide — `[#][Name][Info]`, with `Name` at
`maxWidth: .infinity`. The columns cover the entire row. Today a single click
anywhere on the row selects the cue, and `CueListPane.swift:315-324` turns that
selection into an `engine.seek(...)` plus a `scrollTo`.

So "single click = edit, and don't seek" removes the *only* mouse path to both
selection and seek at once. Selection is not decorative: `Delete`,
`deleteSelected()`, and the context menu's "Renumber Selected…" all depend on it.

The resolution is to split the row into two interaction surfaces:

| Surface | Role |
| ------- | ---- |
| The leading cue-type colour stripe | **the row's handle** — select, seek, extend selection |
| The three text columns | **pure input** — focus a field, never seek |

## Non-goals

Each was raised during the design interview and deliberately deferred.

- **Spreadsheet-style ↑/↓ between rows while editing.** Wanted, and unblocked
  (`InlineEditGate` already disables the bare arrow shortcuts during editing, so
  the keys are free), but it is an independent keyboard-navigation feature with
  its own edge cases (commit-then-move? first/last row? does Tab walk columns?).
  Folding it in would make this PR's three behavioural regressions —
  selection, seek, right-click — impossible to isolate. **Separate issue.**
- **Always-on `TextField`s** (the `LyricsInspectorRow` / `MediaTimecodeRow`
  idiom). Rejected: see Decision 5.
- **Overriding the native text context menu while a field is active.**
- **Drag-to-select across rows** with the mouse. Already unavailable in practice
  and not part of this change.
- **Changing the Figma TypeBar visual** (318:1326). The stripe stays 5pt wide.

## Decisions

| # | Question | Decision |
| - | -------- | -------- |
| 1 | What does a single click on a text cell do? | **Focus that field + select the row. No seek, no scroll.** |
| 2 | Which columns? | **All three** (`#`, `Name`, `Info`) — a table where columns behave differently is worse than a slightly larger change. |
| 3 | Where do selection and seek live now? | **The colour stripe.** Plain click = select + seek. |
| 4 | Multi-select? | **⌘/⇧ + click** on either surface extends selection and suppresses both editing and seek. |
| 5 | Always-on `TextField`, or `Text` → `TextField` on tap? | **Keep the conditional**, change `count: 2` → `count: 1`. |
| 6 | Focus loss while editing a name? | **Commit** — aligns `Name` with `#` and `Info`, which already do this. |
| 7 | May a name be cleared to empty? | **Yes.** |
| 8 | Right-click? | **Unchanged** when idle; **native text menu** while editing. |
| 9 | Show mode (read-only)? | **Fields locked, stripe still seeks.** |

Decision 5 is the one that needs its reasoning recorded, because it looks like a
deviation from the CuePoints reference and isn't. The user-visible behaviour is
identical — one click, caret appears. Keeping the conditional buys two things an
always-on `TextField` would cost:

- **Tail truncation.** `Text` has `.lineLimit(1).truncationMode(.tail)`; a
  `TextField` has no equivalent, so long cue names would scroll inside the field
  instead of ending in `…`.
- **Blank empty names.** An always-on field shows its grey placeholder when the
  name is empty — reintroducing exactly the "Untitled" look that #661 removed.

It also keeps the tap handler in our hands, which Decisions 1, 3 and 4 all need,
and it makes Decision 8 free: an idle cell is still a `Text`, so the row's
`.contextMenu` (`CueListPane.swift:305`) keeps working with no extra code.

## Interaction table

| Action | Selection | Editing | Playhead | Scroll |
| ------ | --------- | ------- | -------- | ------ |
| Click `#` / `Name` / `Info` | set to this row | caret in that field | **unchanged** | none |
| ⌘/⇧ + click any column | toggle this row | none | unchanged | none |
| Click colour stripe | set to this row | none | **seek to cue** | none |
| ⌘/⇧ + click stripe | toggle this row | none | unchanged | none |
| Right-click, idle | unchanged | none | unchanged | none |
| Right-click, editing | native text menu (cut/copy/paste) | | | |
| `Return` | — | commit | | |
| `Esc` | — | cancel, discard draft | | |
| Click elsewhere | — | **commit** | | |
| Show mode | stripe only | fields disabled | stripe seeks | |

## The tap-intent function

Following `InlineEditGate`: the decision is a pure function, unit-tested away
from SwiftUI; the view only performs the result.

```swift
// OnlyCue/UI/CueRowTapIntent.swift
enum CueRowTapTarget { case field, stripe }

enum CueRowTapIntent: Equatable {
    case beginEdit          // select this row, focus the field; no seek
    case extendSelection    // toggle membership; no edit, no seek
    case selectAndSeek      // select this row and move the playhead
    case ignored
}

enum CueRowTap {
    static func intent(target: CueRowTapTarget,
                       isExtending: Bool,
                       isReadOnly: Bool) -> CueRowTapIntent
}
```

Truth table (this *is* the unit test):

| target | isExtending | isReadOnly | → |
| ------ | ----------- | ---------- | - |
| field | false | false | `.beginEdit` |
| field | true | false | `.extendSelection` |
| field | false | true | `.ignored` |
| field | true | true | `.ignored` |
| stripe | false | false | `.selectAndSeek` |
| stripe | true | false | `.extendSelection` |
| stripe | false | true | `.selectAndSeek` |
| stripe | true | true | `.extendSelection` |

`field` + `isReadOnly` is `.ignored` for both modifier states because Decision 9
is implemented by moving `.disabled(isReadOnly)` onto the columns, and a
disabled SwiftUI view receives no taps at all. The table matches reality rather
than describing a branch that can never run.

`isExtending` is read the way `CueMarkersOverlay.swift:159-160` already reads it:

```swift
let m = NSEvent.modifierFlags
let isExtending = m.contains(.command) || m.contains(.shift)
```

A second pure helper covers Decisions 6 and 7, so "clearing a name is legal" is
provable without a UI test:

```swift
enum CueRowNameCommit {
    /// The value to write, or nil when nothing changed.
    /// Trims whitespace; an empty result is a legal name (#661).
    static func value(draft: String, current: String) -> String?
}
```

## Changes

### `CueRowView.swift`

- `count: 2` → `count: 1` on all three cells (`:99`, `:124`, `:152`); each
  handler routes through `CueRowTap.intent(target: .field, ...)`.
- New callbacks: `onSelect: () -> Void`, `onExtendSelection: () -> Void`,
  `onSeek: () -> Void`.
- The stripe overlay (`:58-63`) becomes tappable, gains
  `NSCursor.pointingHand` on hover and `.help("Go to cue")`.
- `commitRename()` (`:161-167`) delegates to `CueRowNameCommit.value`, so empty
  commits through instead of being swallowed.
- `Name` gains `.onChange(of: nameFieldFocused) { if !$1 { commitRename() } }`,
  matching `#` (`:87-89`) and `Info` (`:139-141`).
- `.disabled(isReadOnly)` moves off the row body (`:68`) onto the three columns.

### `CueListPane.swift`

- **Delete `.onChange(of: selection)` (`:315-324`) entirely.** Both of its jobs
  move or die: the `seek` moves into the stripe handler; the
  `scrollTo(anchor: .center)` is dropped, because centring the row you just
  clicked yanks the list out from under the caret. Follow-the-playhead scrolling
  is unaffected — `onChange(of: currentCueID)` (`:328-333`) owns that
  independently and only fires while playing.
- Wire the three new callbacks in `cueRow(for:)` (`:338-355`).
- Check whether `soleSelectedID` (`:85`) has other callers; if not, remove it —
  SwiftLint runs `--strict` in CI.

### Stripe hit area

Visual width stays 5pt. The tappable width becomes 14pt.

**This is narrower than the ~19pt discussed.** The row's content is inset by
`rowLeadingGutter = 14` and the stripe is drawn over `x: 0...5`, so the `#`
column starts at `x: 14`. A 19pt overlay sits *above* the content and would
swallow the first 5pt of the `#` column's clicks. 14pt is the widest value that
takes no clicks away from a column, and it is still ~3× today's target.

```swift
Rectangle().fill(stripeColor)
    .frame(width: CueListLayout.typeStripeWidth)          // 5pt, drawn
    .frame(width: CueListLayout.typeStripeHitWidth,       // 14pt, clickable
           alignment: .leading)
    .contentShape(Rectangle())
```

## Implementation traps

- **`Esc` must not commit.** `cancelRename()` sets `isEditingName = false`,
  which tears down the `TextField`, which drops focus, which fires the new
  focus-loss commit — so `Esc` would silently save the draft it was meant to
  discard. Needs an explicit guard (an `isCancelling` flag, or clearing the
  draft before lowering the flag). `#` and `Info` carry the same latent bug
  today; it is only reachable once focus-loss commit exists on `Name`, but the
  fix should be shared across all three cells rather than special-cased.
- **`.help(...)` needs a string-catalog entry** — this app ships zh-Hant.

## Verification

Two layers, because CI does not cover the second one.

**Unit** (`OnlyCueTests/`) — runs on every PR:
- `CueRowTapIntentTests` — the eight-row truth table above.
- `CueRowNameCommitTests` — no-change → `nil`; whitespace trimmed; **clearing a
  non-empty name yields `""`, not `nil`**.

**UI** (`OnlyCueUITests/`) — the acceptance criterion:

```gherkin
Given a project with a cue named "Verse" at 00:30 and the playhead at 00:00
When I single-click the cue's Name cell and type "Chorus" and press Return
Then the cue is named "Chorus"
And the playhead is still at 00:00
```

Plus: single-click the colour stripe → playhead moves to the cue's time.

⚠️ **CI gates UI tests on push-to-`dev`, so a green PR check does not run
them.** They must be run locally before the PR opens, and the result stated in
the PR's verification block.

Open item: the "playhead did not move" assertion needs an existing accessibility
identifier on the transport's time readout. To be located during implementation;
if none exists, one gets added.
