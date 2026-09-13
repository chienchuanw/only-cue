# Cue fade column + waveform fade preview

**Status:** draft 2026-09-14 — awaiting approval
**Touches:** `OnlyCue/UI/CueListPane.swift`, `OnlyCue/UI/CueRowView.swift`,
`OnlyCue/UI/CueListColumnWidths.swift`, `OnlyCue/UI/CueListLayout.swift`,
`OnlyCue/UI/CueMarkersOverlay.swift`, `OnlyCue/UI/CueMarkersGeometry.swift`,
`OnlyCueTests/`, `OnlyCueUITests/`
**Prior art:** the `#` column plumbing — `CueRowView.numberCell` (`CueRowView.swift:120-143`),
`CueListColumnWidths` number/info entries, the header cell + resize handle
(`CueListPane.swift:188-208`) — copied verbatim for the new Fade column;
`CueMarkersGeometry.position(forTime:width:duration:)` (`CueMarkersGeometry.swift:6-9`)
for the time→x mapping the band reuses.
**Design reference:** Figma `NhH2957iKQ8b581x3gI3Wk` — the existing Cue Mode frame
`318:1228` already carries the FADE column (`FADE` header `318:1324`, cell values
`1.5 s`/`2.0 s`/…). The waveform fade overlay is new: designed in section
`634:3287` ("Cue Fade — column + waveform preview"), detail frame `636:6`. Approved
2026-09-14 (uniform semi-transparent band; see Decision 6).

## Goal

1. Add an editable **Fade** column to the cue list so a designer can type a fade
   time per cue.
2. On the waveform, preview each cue's fade as a **semi-transparent band in the
   cue's type colour**, extending right from the cue point over the fade
   duration.

## What already exists (so this feature adds no data)

`Cue.fadeTime: FadeTime { fadeIn, fadeOut }` is already a persisted field
(`FadeTime.swift:3-6`), already edited through
`CueCommands.setFadeTime(cueId:to:document:undoManager:)` (`CueCommands.swift:99`),
already parsed by `FadeTime.parse` (`"1.5"` symmetric, `"1/2"` split —
`FadeTime.swift:20`), already rendered by `FadeTime.columnDisplay` (`"2.0 s"` —
`FadeTime.swift:49`), and already exported to grandMA2 (`basic_fade`/`basic_outfade`)
and CSV. **No schema bump, no migration.** This feature is a display/edit surface
plus a waveform overlay over data that is already there.

## Non-goals

- **No `TIME` column.** The Figma frame shows a `TIME` column the app lacks; it is
  pre-existing Figma↔app drift, unrelated to fade, and stays out of scope.
- **No removal of the `Info` column.** The Figma mock omits it; the app keeps it.
  Fade is inserted *before* Info (Decision 3).
- **No new fade semantics.** The column is a single symmetric value reusing
  `FadeTime.parse`; power users may still type `"1/2"` to split. `columnDisplay`
  is unchanged.
- **No live-while-typing preview.** The band updates on commit, like every other
  cell (Decision 5).
- **No band-follows-drag polish.** During a retime drag the marker has a
  `visualOffset` (`CueMarkersOverlay.swift:64,85-88`); the band stays at the
  committed `baseX`. Making it ride the drag is deferred.

## Decisions

Settled in the design interview (grilling) + the Figma review.

| # | Question | Decision |
| - | -------- | -------- |
| 1 | Fade column semantics | **Single symmetric value**, reusing `FadeTime.parse`/`columnDisplay`; `"1/2"` split still accepted. |
| 2 | Waveform band direction | **Forward** — `[cue.time, cue.time + fade]`, matching MA2 "fade begins on trigger". |
| 3 | Column order | **`# · Name · Fade · Info`** — Fade between Name and Info. |
| 4 | Which cues show a band | **All cues with `fade > 0`**, always (the waveform is a fade map). |
| 5 | Live vs commit | **Commit** (Enter / focus-loss → `setFadeTime`), matching `#`/Name/Info. |
| 6 | Band fill | **Uniform** cue-type colour at **0.18** opacity, full waveform height. Not a gradient. |
| 7 | Split in/out band length | **`max(fadeIn, fadeOut)`**. |
| 8 | `fade == 0` | **Blank cell, no band** — guarded at the view, `columnDisplay` unchanged. |
| 9 | Show / read-only mode | **Fade cell locked** (rides the existing `.disabled(isReadOnly)` on the column HStack, `CueRowView.swift:55`); **band still drawn** (it's not interactive). |

## Part A — the Fade column

### `CueListColumnWidths.swift`

Add a Fade entry mirroring the Number entry (`:16,25,28,31`):

```swift
static let fadeRange: ClosedRange<CGFloat> = 44...96   // "2.0 s" … "12.0/12.0 s"
static let fadeDefault: CGFloat = 56
static let fadeStorageKey = "cueList.fadeColumnWidth"
static func clampFade(_ w: CGFloat) -> CGFloat { min(max(w, fadeRange.lowerBound), fadeRange.upperBound) }
```

### `CueListLayout.swift` — the #297 floor moves (trap)

`headerHorizontalChrome` (`:48-50`) hard-codes **2** inter-column gaps for
`# · Name · Info`. A third fixed column makes it **3**, and `headerMinimumWidth`
(`:60-64`) must add `fadeRange.lowerBound`:

```swift
static let headerHorizontalChrome: CGFloat =
    3 * rowHorizontalSpacing + rowLeadingGutter + rowHorizontalPadding + 2 * listRowHorizontalInset
// headerMinimumWidth: number.lower + fade.lower + info.lower + headerHorizontalChrome
```

This must stay **≤ `CueListInspectorMetrics.minWidth` (240)** or the outer
`NSSplitView` can't reach its column floor (#297). `CueListPaneMinWidthTests`
guards it. Budget check with `fade.lower = 44`: `40 + 44 + 72 + chrome`; if it
tops 240 the fade floor (or the info floor) is trimmed until the test is green —
tune against the test, don't guess.

### `CueRowView.swift`

New Fade cell between `nameField` and `infoCell` in the row HStack (`:44-50`),
built exactly like `numberCell` (`:120-143`) — `Text` → `TextField` on tap, mono
font, commit on submit / focus-loss:

- New stored props: `fadeColumnWidth: CGFloat = CueListColumnWidths.fadeDefault`,
  `onCommitFade: (FadeTime) -> Void = { _ in }`.
- New `@State fadeDraft`, `@State isEditingFade`, `@FocusState fadeFieldFocused`.
- Idle cell (blank when zero, Decision 8):

```swift
Text((cue.fadeTime == .zero) ? "" : cue.fadeTime.columnDisplay)
    .font(DS.Text.monoSmall)
    .foregroundStyle(DS.Color.textTertiary)
    .frame(maxWidth: .infinity, alignment: .trailing)   // right-aligned, per Figma
    .contentShape(Rectangle())
    .onTapGesture { handleTap(on: .field, beginEditing: beginFadeEdit) }
```

- Edit field seeds from `cue.fadeTime.format()` (canonical `"1.5"`/`"1/2"`), and
  `commitFade()` maps through `FadeTime.parse`:

```swift
private func commitFade() {
    isEditingFade = false
    guard let parsed = FadeTime.parse(fadeDraft), parsed != cue.fadeTime else { return }
    onCommitFade(parsed)
}
```

  Unparseable input (`parse == nil`) is a no-op that reverts — matching how a bad
  number reverts. Column frame uses `.cueColumnFrame(width: fadeColumnWidth,
  range: CueListColumnWidths.fadeRange, alignment: .trailing)`.
- Tokens: `DS.Text.monoSmall` + `DS.Color.textTertiary` keep the cell inside the
  `TokenConformanceTests` gate (`CueRowView.swift` is scanned).

### `CueListPane.swift`

- Add `@AppStorage(CueListColumnWidths.fadeStorageKey)` width + binding, alongside
  the number/info ones.
- Insert a `Text("Fade")` header cell with a `ColumnResizeHandle` between Name and
  Info in `headerRow` (`:198-208`), cloning the Info handle block; identifier
  `cueListFadeColumnResizeHandle`.
- Wire `fadeColumnWidth:` and `onCommitFade:` into `cueRow(for:)`, calling
  `CueCommands.setFadeTime(cueId:to:document:undoManager:)`.

## Part B — the waveform fade band

### `CueMarkersGeometry.swift`

New pure helper next to `position` (`:6-9`):

```swift
/// Pixel width of a fade band: the forward span [t, t+fade] in content space,
/// clamped so it never runs past the content's right edge.
static func spanWidth(forFade fade: TimeInterval, at time: TimeInterval,
                      width: CGFloat, duration: TimeInterval) -> CGFloat {
    guard duration > 0, fade > 0 else { return 0 }
    let end = min(time + fade, duration)
    return max(0, CGFloat((end - time) / duration) * width)
}
```

### `CueMarkersOverlay.swift`

Add a band layer **behind** the marker `ForEach` in the `ZStack`
(`:53-73`), so lines and pins stay on top:

```swift
ForEach(cues) { cue in
    let fade = max(cue.fadeTime.fadeIn, cue.fadeTime.fadeOut)
    let w = CueMarkersGeometry.spanWidth(forFade: fade, at: cue.time,
              width: geometry.size.width, duration: duration)
    if w > 0 {
        Rectangle()
            .fill(Color(hex: resolveColorHex(cue) ?? "") ?? .accentColor)
            .opacity(Self.fadeBandOpacity)          // 0.18, named constant
            .frame(width: w, height: geometry.size.height)
            .offset(x: CueMarkersGeometry.position(forTime: cue.time,
                      width: geometry.size.width, duration: duration))
            .allowsHitTesting(false)                // never steals seek/drag
    }
}
```

- `fadeBandOpacity: Double = 0.18` — matches the approved Figma alpha and the
  existing `CueListLayout.rowTintOpacity = 0.18` (`CueListLayout.swift:9`); declared
  as a named `static let` for intent.
- `geometry.size.width` is already the zoomed **content** width (the overlay lives
  inside the zoom-scaled content), so the band scales with zoom for free — the
  same width the markers use (`:60`).
- `CueMarkersOverlay.swift` is **not** in the `TokenConformanceTests` file list, so
  the `Color(hex:)` fill and `.opacity` are fine; the named constant is for
  readability, not the gate.

## Verification

**Unit** (`OnlyCueTests/`) — runs on every PR:

- `CueMarkersGeometryTests` (new or extended):
  - `spanWidth` — `fade == 0 → 0`; `fade == duration → width`; a mid value maps
    linearly; a fade that overruns the end **clamps to the right edge**
    (`time + fade > duration`).
- `FadeCellDisplayTests` (new, pure): `cue.fadeTime == .zero → ""`; non-zero →
  `columnDisplay`. (Guards Decision 8 without a UI test.)
- `CueListColumnWidthsTests` (extend): `clampFade` clamps to `fadeRange`.
- `CueListPaneMinWidthTests` (existing): stays green after the chrome/floor change
  — **the gate on Part A's #297 trap.**
- Confirm `CueCommandsTests` covers `setFadeTime` undo; add a case if absent.

**UI** (`OnlyCueUITests/`) — the acceptance criteria (mirrored as BDD):

```gherkin
Scenario: type a fade in the cue list
  Given a project with a cue "Verse 1" and the Fade cell blank
  When I single-click the cue's Fade cell, type "2", and press Return
  Then the Fade cell reads "2.0 s"
  And the cue's fadeTime is 2.0 s in / 2.0 s out

Scenario: fade renders a band on the waveform
  Given a cue at 00:30 in a 03:00 clip with fade 3.0 s
  Then a fade band in the cue's type colour spans 00:30 → 00:33 on the waveform
```

⚠️ **CI gates UI tests on push-to-`dev`, so a green PR check does not run them.**
Run them locally before the PR and state the result in the PR verification block.

Open item: the band's XCUITest assertion needs a queryable identifier on the band
(e.g. `fadeBand-<cue.id>`); to be added during implementation, mirroring
`cueMarker-<id>` (`CueMarkersOverlay.swift:293`).

## Rollout notes

- All existing cues default to `fadeTime == .zero`, so on first run every Fade
  cell is blank and no bands draw — the feature is purely additive and invisible
  until a value is typed.
- App order (`# · Name · Fade · Info`) diverges from the Figma mock's
  `TIME · # · NAME · FADE`; that is the pre-existing drift called out in Non-goals,
  not introduced here.
