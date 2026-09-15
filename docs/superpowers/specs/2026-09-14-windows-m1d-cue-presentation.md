# Windows M1d — Cue-List Presentation Contract

**Epic:** #728 · **Parent spec:** `docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`
**Status:** proposed · **Date:** 2026-09-14

Settles what "`OnlyCue.App.ViewModels` and the WinUI shell follow as separate
work" actually means, now that M1a–M1c have landed and the macOS side has been
read rather than assumed.

## The finding that changes the parent spec

The parent spec provisioned an `OnlyCue.App.ViewModels` assembly on the premise
that macOS has a view-model layer to mirror. **It does not.** The cue list is
"view-native": presentation logic lives in two places, neither of which is a
view model.

1. **Pure helpers, already isolated and already unit-tested** —
   `FadeTime` (`OnlyCue/Document/FadeTime.swift`), `CueRowFill`
   (`OnlyCue/UI/CueRowFill.swift:21`), `CueRowTap`
   (`OnlyCue/UI/CueRowTapIntent.swift:39`), `CueListSectionHeader.countText`
   (`OnlyCue/UI/CueListSectionHeader.swift:35`), `CueNumberValidator`
   (`OnlyCue/Commands/CueNumberValidator.swift:26`), `CueNumberErrorMessage`
   (`OnlyCue/UI/CueNumberErrorMessage.swift:17`).

2. **Decision logic inlined into SwiftUI view properties** — the Show-mode
   GO-by-type filter resolution, row opacity, current-cue resolution
   (`OnlyCue/UI/CueListPane+RowBackground.swift:25-46`) and the empty-state
   copy (`OnlyCue/UI/CueListPane.swift:169-188`).

This is better news than the parent spec assumed. Category 1 is exactly what a
golden vector can pin, and category 2 becomes pinnable by a behaviour-preserving
extraction. So M1d is **not** "invent a view-model layer" — it is **vector 8**,
and the thing that genuinely has no macOS counterpart (observable glue, XAML)
shrinks to a separate Windows-only slice.

## Two decisions

- **D3 — pin the view glue too.** Category 2 is extracted into pure Swift types
  so it enters vector 8. This touches macOS UI code, which is wider than the
  usual surgical rule, and is accepted deliberately: the alternative leaves four
  behaviours on Windows with no contract, which is precisely the blind spot that
  hid four real port bugs in M1c.
- **D4 — presentation logic lands in `OnlyCue.Core`.** The invariant stays
  crisp: **vector-pinned ⇔ in `OnlyCue.Core`.** `OnlyCue.App.ViewModels` is then
  only what its name says — `INotifyPropertyChanged` glue with no logic worth
  pinning.

## Prerequisites — #829 and #830 are fixed first

Two known macOS bugs sit inside vector 8's surface. They are fixed **before** the
vector is generated, so it pins corrected behaviour rather than baking a defect
into the cross-platform contract:

1. **#829** — `FadeTime.formatNumber` traps above `Int64.max`. It is in the
   `fadeFormat` group, and the macOS generator cannot emit a vector case for a
   value it crashes on. The fix belongs in `parseNonNegative` (the trust
   boundary), with `formatNumber` made total as belt-and-braces.
2. **#830** — negative cue numbers emit the malformed token `-1.-5`. Investigated
   while writing this spec, and the first reading was **wrong**: it found
   `CueCommands.setCueNumber` (`OnlyCue/Commands/CueCommands.swift:91`), saw that
   it gates on `CueNumberValidator` (`minimum` `0.001`), and concluded a negative
   number could not be entered through the UI at all. It called
   `setCueNumber` "the only UI path" without checking, and there are three
   writers of `cueNumber`, not one — `setCueNumber`, `autoFillCueNumbers` and
   `renumberSelected`, and only the first consulted the validator.
   `renumberSelected` was a live UI path to a negative number:
   `RenumberCuesSheet` binds `start` to a plain `TextField`, and the
   `Stepper(in:)` beside it constrains only the stepper buttons, so a typed
   `-1.5` arrived unfiltered and reached the MA2 generators.

   So #830 is **two** defects, not one, and needs both halves:

   - *Live UI defect* — closed by the domain guard now at
     `CueCommands+Renumber.swift:34`, which rejects the whole run rather than
     numbering half of it. (`autoFillCueNumbers` is safe for a different
     reason: `CueNumberAutoFill.assignments` generates its own numbers and
     never takes one from the user.)
   - *Trust-boundary defect* — `Cue.swift:50` decodes `cueNumber` via
     `decodeIfPresent` with **no validation**, so a hand-edited or corrupted
     `.cuelist` is a second way in. Fixed at decode by coercing an
     out-of-domain number to `nil` (unnumbered) rather than clamping it or
     failing the load.

   The lesson worth keeping: "the only path" is a claim about *all* the code,
   and a `grep` for the property — not for the function — is what checks it.

#830 forces `golden/ma2-telnet-v1.json` and `golden/ma2-export-v1.json` to be
regenerated and `Ma2CueNumber.cs` updated in the same change; the drift guard
fails loudly until that happens, which is the intended safety net.

## Scope split

| Slice | Content | Buildable on macOS |
|---|---|---|
| **M1d** (this spec) | Swift extraction + `golden/cue-presentation-v1.json` + `OnlyCue.Core` implementation + xUnit verifier | **Yes, end to end** |
| **M1e** (deferred) | `OnlyCue.App.ViewModels` observable glue + WinUI XAML shell | No — WinUI 3 cannot build on macOS |

M1d is the last slice that a Mac-only agent can complete with full confidence.
M1e needs real Windows for visual sign-off and is specified separately.

## Vector 8 — `golden/cue-presentation-v1.json`

Generated by `OnlyCueTests/CuePresentationGoldenVectorTests.swift` following the
established bootstrap-and-fail / byte-compare pattern, with fixtures split into
`CuePresentationGoldenFixtures.swift` from the start (the M1c file-length lesson).

| Group | Swift source of truth | Pins |
|---|---|---|
| `fadeParse` | `FadeTime.parse` | the accept/reject grammar incl. the divergences below |
| `fadeFormat` | `FadeTime.format`, `.cellDisplay` | symmetric vs. split spelling; zero blanks |
| `cueNumberValidation` | `CueNumberValidator.validate` | `.ok` / `.invalidFormat` / `.duplicate` / `.outOfRange` + both bounds |
| `cueNumberErrors` | `CueNumberErrorMessage.text` | the exact user-facing strings, byte for byte |
| `sectionCount` | `CueListSectionHeader.countText` | singular/plural/zero |
| `rowTapIntent` | `CueRowTap.intent` | all six `(target, isExtending, isReadOnly)` combinations |
| `rowFill` | `CueRowFill.Resolution` *(new)* | the branch chosen, not the `Color` |
| `goFilter` | `CueListGoFilter.resolve` *(new)* | raw id + live types + read-only → resolved filter |
| `rowOpacity` | `CueListRowOpacity.value` *(new)* | dimmed vs. full |
| `activeCue` | `MediaItem.activeCue(at:typeID:)` | playhead → live cue, incl. type filter and boundaries |
| `emptyState` | `CueListEmptyState.message` *(new)* | the two copy variants |

`FadeTime.formatNumber` is **not** re-pinned: `golden/ma2-telnet-v1.json` already
pins it and `windows/OnlyCue.Core/Document/FadeTimeFormatting.cs` already
implements it.
Vector 8 consumes it.

### Encoding

Identical rules to vectors 1–7 — `.prettyPrinted, .sortedKeys,
.withoutEscapingSlashes`; doubles as round-trip-exact decimal strings compared
bitwise via `GoldenDouble`; fixed literal ids, never `UUID()`.

## macOS extractions (behaviour-preserving)

Four new pure types, each lifted verbatim out of a view property. The existing
call sites delegate to them, so `CueRowFillTests`, the cue-list XCUITests and the
Show-mode suites all keep passing unchanged — that is the regression harness.

- `CueRowFill.Resolution` — `{ current, tint, selectionFallback, clear }`.
  `CueRowFill.color(...)` becomes a `switch` over it. The existing signature and
  return type are untouched.
- `CueListGoFilter.resolve(rawID:types:isReadOnly:)` — the body of
  `CueListPane.showGoTypeID`. Note `DocumentView.showGoTypeID` must delegate to
  the same function; the "keep that invariant" comment at
  `CueListPane+RowBackground.swift:21-23` currently relies on a human noticing.
- `CueListRowOpacity.value(cueTypeID:filter:dimmed:)` — the body of `rowOpacity`.
- `CueListEmptyState.message(hasActiveItem:)` — the ternary at
  `CueListPane.swift:171-173`.

## Confirmed cross-platform divergences

Measured on this machine (Swift 6.3.3 / .NET 10.0.11), not assumed. Each gets a
vector case, and each is mutation-tested — which is not the same as each being
load-bearing. A guard whose mutant survives is not automatically a gap; see the
mutation section for how the two that survived were told apart.

| Input | Swift `FadeTime.parse` | Naive C# port | Cause |
|---|---|---|---|
| `"1.5\n"`, `"1.5\r"` | **nil** | `1.5` | Swift `.whitespaces` is `Zs`+tab and excludes newlines; .NET `Trim()` strips them |
| `"1.5\t"`, `"\u{00A0}1.5"` | `1.5` | `1.5` | agree — both trim tab and NBSP |
| `"0x1p3"` | **nil** (was `8.0`) | reject | Swift's `Double(String)` implements the whole C99 `strtod` grammar; .NET has none. Closed on the **Swift** side — see #841 below |
| `"+1"` | **nil** | `1.0` | rejected only by the explicit `hasPrefix("+")` guard; .NET `NumberStyles.Float` allows a leading sign |
| `"infinity"`, `"nan"` | nil | nil | .NET `TryParse` **accepts** both spellings whatever the styles, so only the port turns them away — and the `0...maximum` bounds are what do it |
| `"1."`, `".5"` | `1.0`, `0.5` | same | agree |

**#841 — the hex-float divergence was resolved by changing macOS, not the port.**
This is the one case where the port did not simply mirror what Swift already
did, so it is worth stating why. `FadeTime.parse("0x1p3")` returned an 8 second
fade because `Double(String)` accepts C99 hex floats — nobody types that into a
fade field on purpose, so accepting it was a bug on its own terms, not merely an
inconvenience for the port. The options were to teach the port a hex-float
grammar or to narrow the macOS one; narrowing won, because the alternative
spreads a grammar neither platform's users want across both cores. Swift now
rejects any `0x` prefix explicitly.

The consequence for the port is that it needs **no** counterpart guard: .NET has
no hex-float grammar, so every `0x…` spelling is already rejected by the
narrowed `NumberStyles` (measured, including `"0x10"` and `"-0x0p0"`). Adding
one anyway would be dead code no mutation could kill, which reads as protection
that isn't there. The vector's hex cases pin the shared *rejection*, and also
pin that the macOS fix did not leak into decimal spellings that merely begin
with a zero (`"00.5"`, `"0e0"`).

Two further notes, both negative results worth recording so a reviewer need not
re-derive them:

- **`max(by:)` / `min(by:)` tie-breaking is safe here.** Swift and .NET
  `MaxBy`/`MinBy` both return the **first** extremal element (measured). So
  `activeCue` and the validator's neighbour lookup do **not** reproduce #834 —
  that issue is about an unstable *sort*, a different mechanism.
- **`CueNumberErrorMessage.invalidFormat` contains U+2013 EN DASH**
  (`e2 80 93`), not a hyphen. Byte-for-byte comparison is what catches a port
  that types the ASCII character.

## Mutation testing (mandatory)

Per the M1c discipline, a first-try-green C# run proves nothing. Each hazard gets
a deliberate mutant, and a surviving mutant must be resolved empirically as
either a genuine coverage gap or a provably equivalent implementation:

`Trim()` instead of the Swift whitespace set · dropping the `+` guard · dropping
`IsFinite` · hyphen for en dash · `MaxBy` swapped to last-wins · `.ok` returned
before the duplicate check · row-fill branch order inverted (`isSelected` tested
before `isCurrent`).

**Result: 30 mutants, 28 killed, 2 survived — both proven equivalent
empirically rather than by argument**, which is the part that matters, since
"this mutant is equivalent" is exactly what someone with a coverage gap would
also say.

- *Dropping `IsFinite`* — survives. The `0...maximum` bounds already reject
  every non-finite value: `+∞` and `NaN` both fail `<= 3600`, `-∞` fails
  `>= 0`. Evaluated directly rather than reasoned about. The check stays
  anyway — stated, not relied upon — because reordering the bounds or folding
  them into a clamp helper would silently change the non-finite answer. The
  same mutant survives on the Swift original, so the two cores match here too.
- *`!(lower < number)` weakened to `lower < number` on the equality edge* —
  survives because the branch is **unreachable**, not because it is untested. A
  candidate equal to a neighbour's number is returned as `Duplicate` before the
  ordering rule runs. Proven by instrumenting the validator to `throw` if the
  ordering check was ever reached with `previous == number` or `next == number`:
  121 tests passed and the probe never fired. A separate mutant already pins
  that the duplicate check precedes the ordering one, so the ordering that makes
  this branch unreachable cannot itself be silently removed.

## Out of scope

Everything the parent spec excludes, plus: WinUI XAML, `INotifyPropertyChanged`
glue, `ObservableCollection` wiring, drag-reorder, the inspector panes, waveform
and timeline presentation. Range selection is explicitly out — #790 is an open
macOS bug, and porting a behaviour that is about to change would pin the wrong
contract.

## Acceptance

- `golden/cue-presentation-v1.json` committed, byte-stable across repeat runs.
- Deleting it and re-running regenerates **and fails**, as with vectors 1–7.
- `dotnet test` green on `windows-latest`; `swiftlint --strict` clean.
- The full Swift suite stays green with **no test edited to accommodate the
  extraction** — any edit needed is evidence the refactor changed behaviour.
- Every mutant in the list above kills at least one assertion.

## Risks

- **The extraction changes behaviour silently.** Mitigated by refusing to edit
  any existing test; the UI suites are the harness. Note these run only on
  push-to-`dev`, never on PRs, so they must be run locally before the PR.
- **The prerequisite fixes change an already-shipped contract.** #830 in
  particular rewrites two committed vectors and the C# that mirrors them. The
  risk is a partial landing — Swift fixed, C# not — which the drift guard
  catches, but only once CI runs. Both must move in one commit.
- **Choosing #829's clamp value is a product decision, not a mechanical one.** A
  fade bound also implies what happens to an already-saved document carrying a
  larger value. That belongs to #829's own issue and is not pre-empted here.
- **Scope creep into the inspector.** `CueNumberErrorMessage` is shared with the
  inspector; only the cue-list path is in scope.
