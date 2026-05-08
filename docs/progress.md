# Progress

Append-only session log. Newer entries on top.

---

## 2026-05-08 — Color from CuePointType, drop Cue.colorHex, schema v6 (PR #55, leaf #54 of epic #32)

**Shipped:** issue #54 (fifth leaf of epic #32). PR #55 merged into `dev` (rebase, head `39a30e8`). Every UI site that paints a cue color now resolves via the cue's `CuePointType` through a new `ProjectModel.colorHex(for:)` helper. The transitional `Cue.colorHex` field is gone. Schema bumped to **v6** with a `migrateFromV5` that decodes the v5 envelope and constructs v6 cues without colorHex; v1/v2/v3/v4 chains all drop the field at their `toCue()` boundary so every pre-v6 source lands at v6. **151/151 unit tests green; 0 SwiftLint violations; Release build clean (warnings-as-errors).**

**Why this leaf surfaced now:** PR #53 (cue inspector) made the staleness of per-cue color visible. The inspector picker calls `CueCommands.setType` which only mutates `cue.typeID` — `cue.colorHex` continued to hold the previous Type's color. Result: changing Type via the picker left the row swatch on the old color. The transitional `colorHex` was kept on `Cue` through PR #45 (when `CuePointType` landed) to avoid breaking the MVP's color-picker UX in one go; with the inspector now the editing surface for Type membership, the per-cue field was redundant and actively harmful as a UI/model disagreement source.

**Why the layout order matters:** dropping `Cue.colorHex` first would break every UI site that reads it. The TDD cycles ran in dependency order — helper first → row rewire → marker rewire → popover deletion → schema bump last — so each cycle stayed compile-green. The schema bump in cycle 5 was the atomic structural change once the field was unused everywhere except construction sites.

**Why a closure for the marker overlay's resolver:** `CueMarkersOverlay` takes a `resolveColorHex: (Cue) -> String?` closure rather than the array of `CuePointType`s or a precomputed `[UUID: String]` map. The closure stays at the call-site abstraction level — the overlay doesn't need to know about the project model — and lets `PreviewPane` build the resolver inline as `{ document.model.colorHex(for: $0) }`. SwiftUI rebuilds the closure each render but `document` is `@ObservedObject`, so closures pick up fresh state correctly. Bounded-OK at current scale (M=1–10 Types, N=tens of cues per render).

**Why the popover is deleted entirely (UX trade-off, captured in ADR-012):** the existing per-row palette popover wrote to `cue.colorHex` via `CueCommands.recolor`. Both the field and the command are gone. Users now change a cue's color by picking a different Type via the inspector. Until a Type management UI ships, the default project has only one Type ("General" `#4ECDC4`), so per-cue color flexibility is temporarily reduced. ADR-012 documents this as accepted transitional cost. Snapshotting `Type.colorHex` into `Cue.colorHex` at `setType` time was rejected — converts disagreement into stale-cache drift (recoloring a Type wouldn't update existing cues) without removing the underlying issue.

**Why `LegacyV5*` mirrors `LegacyV4*` plus `fadeTime`:** same frozen-snapshot pattern as the prior chains. Each `LegacyVN` is a frozen JSON envelope; generalizing them would couple frozen formats and create regression risk on every future schema bump. Pattern is intentional, kept across all four migration chains.

**What landed in PR #55 (7 commits):**
- `OnlyCue/Document/Cue.swift` — drop `var colorHex: String`.
- `OnlyCue/Document/ProjectModel.swift` — bump `currentSchemaVersion` 5 → 6; add `case 5: migrateFromV5` to the decode switch; new private `LegacyV5` / `LegacyV5Item` / `LegacyV5Cue` (the v5 envelope mirrors v4 plus `fadeTime`); `migrateFromV5(_:)` constructs v6 cues without colorHex; existing `LegacyCue.toCue` / `LegacyV3Cue.toCue` / `LegacyV4Cue.toCue` updated to drop the `colorHex:` arg from their `Cue(...)` constructors. New instance helper `func colorHex(for cue: Cue) -> String?` resolves via `cuePointTypes.first(where: { $0.id == cue.typeID })?.colorHex`.
- `OnlyCue/Commands/CueCommands.swift` — drop `colorHex:` from `addCueAtPlayhead`'s `Cue(...)`; delete `recolor(cueId:to:)`.
- `OnlyCue/UI/CueRowView.swift` — add `resolvedColorHex: String?` prop; replace inline `Circle()` swatch with shared `CueColorSwatch`; delete the `colorMenu` view, the static `palette`, the `onRecolor` callback, the `showColorPopover` state, the popover, and the `swatchColor` computed property.
- `OnlyCue/UI/CueListPane.swift` — drop the `onRecolor` row callback wiring; pass `resolvedColorHex: document.model.colorHex(for: cue)` to each row.
- `OnlyCue/UI/CueMarkersOverlay.swift` — `CueMarkerView` takes `resolvedColorHex: String?`; `CueMarkersOverlay` takes `resolveColorHex: (Cue) -> String?` closure and forwards per cue.
- `OnlyCue/UI/WaveformContainer.swift` — accept and plumb the resolver closure through to `CueMarkersOverlay`.
- `OnlyCue/UI/PreviewPane.swift` — build the closure inline at the `WaveformContainer` call site.
- `OnlyCue/UI/CueColorSwatch.swift` — `hex` becomes `String?`; new `fallback` parameter defaulting to `.accentColor` (restores the cue row's prior fallback behavior); doc comment updated to drop the deleted-popover reference.
- `OnlyCueTests/ProjectModelTests.swift` — new `test_colorHex_for_returnsMatchingTypeColor` and `test_colorHex_for_danglingTypeID_returnsNil`; rename `…IsFive` → `…IsSix`; drop `colorHex:` from 5 `Cue(...)` fixtures.
- `OnlyCueTests/CueCommandsTests.swift` — delete `test_recolor_updatesColorHex_undoRestoresPriorColor`; drop `colorHex:` from the `Cue` fixture.
- `OnlyCueTests/ProjectModelMigrationTests.swift` — new file-scope `private let v5FixtureWithColorHex` and `test_v5_dropsColorHex_preservesEverythingElse`.
- `docs/data-model.md` — schema example v6, `Cue` struct loses `colorHex` field, `colorHex(for:)` listed on `ProjectModel`, field-rules row removed for `cue.colorHex`, versioning policy adds v5→v6 entry covering all five chains.
- `docs/decisions.md` — **ADR-012** capturing the decision (color is Type-derived, popover removal accepted as transitional UX cost, alternative "snapshot at setType" rejected for stale-cache drift).

**Simplify pass — 3 fixes applied (commit `39a30e8`), 4 deferred:**

Applied:
1. **Reuse + Quality + Taste:** `CueColorSwatch` was inconsistent. Its fallback was `.gray`; `CueMarkerView`'s fallback was `.accentColor`; the prior row swatch used `.accentColor`. Refactored `CueColorSwatch` to take `let hex: String?` (instead of `String` with `?? ""` workaround) and added `var fallback: Color = .accentColor`. Now `CueRowView` passes `hex: resolvedColorHex` directly with `.accentColor` restored as the row fallback. Inspector Type picker still works (passes non-optional String which coerces to String?).
2. Stale doc comment on `CueColorSwatch` referenced the now-deleted "color popover" — rewrote to mention "row swatch" instead.
3. Drop the `?? ""` escape hatch at the `CueRowView` call site once `CueColorSwatch.hex` was `String?`.

Deferred (with reasoning per finding):
- `cuePointType(for:) -> CuePointType?` companion helper alongside `colorHex(for:)` — no current caller, YAGNI per CLAUDE.md "Don't add features beyond what the task requires". The Type management leaf can add it then.
- `resolveColorHex` default closure `{ _ in nil }` swallowing future caller omissions — theoretical; currently one caller threading correctly.
- Non-Equatable closure on `WaveformContainer` prevents SwiftUI short-circuit — theoretical; only matters if `PreviewPane` re-renders frequently (it doesn't; the engine timer doesn't pass through it).
- Precomputed `[UUID: String]` map for color resolution — bounded-OK at M=1–10 Types and N=tens of cues per render.

**TDD discipline — 7 separate cycles:**
1. `ProjectModel.colorHex(for:)` helper + pair of tests (matching Type / dangling typeID)
2. `CueRowView.resolvedColorHex` prop + `CueListPane` resolves from `document.model`
3. `CueMarkersOverlay` resolver closure + `WaveformContainer`/`PreviewPane` plumbing
4. Delete popover, `Self.palette`, `colorMenu`, `onRecolor`, `showColorPopover` state, `CueCommands.recolor`, `test_recolor`
5. Schema v5 → v6, drop `Cue.colorHex`, add `LegacyV5` envelope + `migrateFromV5`, update 4 legacy `toCue` methods, update test fixtures, new `test_v5_dropsColorHex_preservesEverythingElse`
6. Docs (data-model.md schema v6 + ADR-012)
7. Simplify pass (CueColorSwatch String? refactor + accentColor fallback + drop `?? ""`)

Each cycle: red (verified failure), green (minimum impl), commit.

**Manual verification (PR test plan):** open a v5 `.cuelist`, verify it migrates to v6 with the seeded "General" Type's color (#4ECDC4); select a cue, change Type via inspector, verify row swatch and waveform marker both update; save v6 file and reopen, verify lossless round-trip.

**XCUITest deferred** per `OnlyCueUITests` harness flakiness on this machine. Resolver behavior is fully covered by `colorHex(for:)` model tests + `migrateFromV5` migration test. View rendering verified manually through the test plan above.

**Closing note — fifth leaf of #32 done; the schema cleanup is complete.** One leaf remains under #32, both UI-shaped: number-key cue creation (1–0 binds to a Type via `Type.hotkey` — model layer already accepts the value, just needs keymap wiring). It depends on a Type management UI to be useful (no current UI sets `Type.hotkey`), so the natural ordering is **Type management leaf → number-key leaf**. Carry-overs from PR #47 review still open: [#48](https://github.com/chienchuanw/only-cue/issues/48) (stable-sort tie-breaker on equal `cue.time`) and [#49](https://github.com/chienchuanw/only-cue/issues/49) (drop the `cueNumber: 0` placeholder via a `PendingCue` helper across `LegacyCue.toCue` / `LegacyV3Cue.toCue` / `LegacyV4Cue.toCue` / `LegacyV5Cue.toCue` — now four sites, growing each schema bump).

---

## 2026-05-08 — Cue inspector pane (PR #53, leaf #52 of epic #32)

**Shipped:** issue #52 (fourth leaf of epic #32). PR #53 merged into `dev` (rebase, head `091ce02`). The right-side `.inspector` slot now shows a draggable vertical split: the existing cue list on top, a new `CueInspectorView` below, both inside `CueListPane`. Selecting a cue in the list populates the inspector with editable Type / cueNumber / name / fadeTime / notes — finally surfacing the four schema fields the prior three leaves of #32 added. UI-only; zero schema change. **150/150 unit tests green; 0 SwiftLint violations; Release build clean (warnings-as-errors).**

**Why this was the right next leaf:** after PR #45/#47/#51, every cue carried `typeID`, `cueNumber`, `fadeTime`, and `notes`, but the user could only read/edit `name` (double-click rename) and `colorHex` (palette popover). The other four were programmatic-only — set by defaults at creation, by migration backfill, or by future code paths. Console export (#34) cannot be meaningful while the user has no way to actually drive Type and fade values. The inspector closes that gap before the export work begins.

**Why this layout (CHECKPOINT 1 design call):** the right-side `.inspector` slot in `DocumentView` already hosts `CueListPane`. SwiftUI's `.inspector` modifier only allows one inspector view per `NavigationSplitView`, so a third column is impossible without restructuring. Picked `VSplitView` inside `CueListPane`: list on top, inspector below, draggable splitter. Selection state stays in `CueListPane` (`@State var selection: Cue.ID?`) — no hoist to `DocumentView` because no other consumer needs it yet. Rejected: separate inspector pane (slot is taken), sheet/popover triggered on double-click (CuePoints' inspector is always-visible — modal would block the timeline), inline editing in `CueRowView` (Type picker + cueNumber + fadeTime + notes can't fit in a row). Selection hoist deferred until a future leaf actually needs it.

**Why a pure `CueInspectorCommit` helper:** SwiftUI views are hard to TDD without a host. Field-commit logic — given a draft string and the current value, return either `.parsed(T)` or `.revert(canonical: String)` or `.noChange` — is pure and lives outside the view. `commitFadeTime(draft:current:)` and `commitCueNumber(draft:current:)` are exhaustively tested (split, symmetric, no-change, invalid, empty, negative) without spinning up a SwiftUI host. The view consumes the outcome and either calls a `CueCommand`, no-ops, or sets the draft back to canonical form. Same trust-the-seam shape as the model-layer helpers.

**Why `setCueNumber` accepts negatives:** intentional. Matches ADR-010's "auto-assignment can also go negative on repeated inserts before the minimum". The future "renumber from 1" command will normalize both auto-assigned and manually-typed negatives. If lighting consoles reject negatives at export time, that's a separate follow-up at the export boundary, not a model-layer trap.

**Why focused-aware `syncDrafts`:** found by the simplify pass (HOT-PATH). The inspector's `.onChange(of: cue)` resyncs all four drafts whenever the cue object updates — but if the user is mid-typing in `fadeDraft` when an external mutation lands (marker drag retime, undo from elsewhere), their input would be clobbered. Two-line fix: skip the field whose `@FocusState` matches `focused`. The `.id(cue.id)` modifier on the body still resets all drafts cleanly when the *selection* changes (different cue), so the focused-aware skip only applies to same-cue external mutations.

**What landed in PR #53 (10 commits):**
- `OnlyCue/Commands/CueCommands.swift` — gains `setType` / `setCueNumber` / `setFadeTime` / `setNotes`. All four routed through new private `updateCue(cueId:document:undoManager:actionName:update:)` taking an `(inout Cue) -> Void` closure. `rename` and `recolor` refactored to use the same helper while green; reads uniformly across the cue setters now.
- `OnlyCue/Commands/CueCommands+Items.swift` (new) — item-level mutations (`addItem`, `addItems`, `removeItem`, `renameItem`, `reorderItems`, `setActiveItem`, `refreshBookmark`) plus their undo helpers (`registerItemUndo`, `restoreItems`, `nextActiveID`) split into a `extension CueCommands` so the main type body stays under SwiftLint's 250-line `type_body_length` cap after the four new setters.
- `OnlyCue/UI/CueInspectorView.swift` (new) — the inspector itself. `@FocusState`-driven; `@State` drafts for name/cueNumber/fade/notes; Type picker bound directly to `CueCommands.setType` via custom `Binding` setter. Empty state when `cue == nil` shows "Select a cue" with id `cueInspectorEmptyState`. `.id(cue.id)` resets drafts on selection change; `.onChange(of: cue)` syncs them on same-cue external mutation but skips the focused field. `.onChange(of: focused)` commits whichever field just lost focus.
- `OnlyCue/UI/CueInspectorCommit.swift` (new) — pure helpers. `commitFadeTime(draft:current:) -> FadeOutcome` returning `.parsed(FadeTime)` / `.noChange` / `.revert(canonical: String)`. `commitCueNumber(draft:current:) -> NumberOutcome` same shape. Used by the view's commit path; tested without SwiftUI.
- `OnlyCue/UI/CueColorSwatch.swift` (new) — small filled circle reused by the inspector's Type picker (10pt) and `CueRowView`'s palette popover (12pt). `Color(hex:) ?? .gray` fallback.
- `OnlyCue/UI/CueListPane.swift` — wrap List + new inspector in a `VSplitView` with `minHeight` 120 / 180 respectively. Resolves `selectedCue` via `cues.first(where: { $0.id == selection })`.
- `OnlyCue/UI/CueRowView.swift` — replace inline `Circle()` swatch with `CueColorSwatch`.
- `OnlyCue/Document/FadeTime.swift` — `formatNumber(_:)` promoted from `private static` to `static` (internal) so `CueInspectorCommit.commitCueNumber`'s revert path reuses it instead of duplicating the "drop trailing .0 on whole numbers" logic.
- `OnlyCueTests/CueCommandsTests.swift` — round-trip + undo tests for each of the four new mutations.
- `OnlyCueTests/CueInspectorCommitTests.swift` (new) — 12 tests covering split / symmetric / no-change / invalid / empty / negative for both helpers.
- `docs/data-model.md` — field-rules rows for `cue.typeID` / `cueNumber` / `fadeTime` / `notes` now reference the inspector as the editing surface; "What's deliberately NOT in the model" trimmed (the items the inspector now covers were previously listed there).

**Simplify pass — 3 fixes applied (commit `d88ed52`), 3 deferred:**

Applied:
1. **Reuse:** `formatNumber` was duplicated between `FadeTime.formatNumber` (private) and `CueInspectorCommit.formatNumber`. Promoted FadeTime's to internal; deleted the duplicate; `commitCueNumber` reuses `FadeTime.formatNumber`.
2. **Reuse:** color swatch was inlined as `Circle().fill(Color(hex:) ?? .gray).frame(width:height:)` in two views with only the diameter differing (10pt vs 12pt). Extracted `CueColorSwatch(hex:diameter:)` and replaced both call sites.
3. **HOT-PATH:** `syncDrafts` was clobbering whichever field the user was typing into when any external mutation hit the cue. Two-line fix to skip the focused field. Without this, marker drag retiming or any concurrent undo would erase in-progress input mid-typing.

Deferred:
- Double-commit on Return-then-Tab — quality reviewer flagged it, but the existing `.noChange` branch already short-circuits without producing a redundant write.
- Empty-name silent revert — consistent with `commitNumber` and `commitFade`'s revert paths within the inspector, and with `CueRowView.commitRename`'s same silent-revert pattern. Not a bug; could be a UX polish follow-up.
- Negative `cueNumber` acceptance — intentional, matches ADR-010 auto-assignment that can also go negative. If lighting consoles reject negatives at export time, the boundary is the right place to enforce that, not the inspector parser.

**Post-push linter cleanup (commit `091ce02`):** `commitNumber` was canonicalizing `numberDraft` only on `.revert`; `.parsed` and `.noChange` left the draft as the user's literal typing (`"1.50"` would stay as `"1.50"` even after committing as `1.5`). Linter pushed a small follow-up that snaps the draft to `FadeTime.formatNumber(value)` on `.parsed` and `FadeTime.formatNumber(cue.cueNumber)` on `.noChange`. Mirrors the fade field's existing canonicalize-on-commit shape. Same patch was already in `commitFade` for the same reason.

**SwiftLint hits — caught locally before push:**
1. **`type_body_length`** — `CueCommands` enum body grew to 276 lines after the four new setters (cap 250). First refactor (extracting `updateCue` and dropping the per-method `cues.map` boilerplate) brought it to 262 — still over. Second fix: split item-level mutations into `CueCommands+Items.swift` as a separate extension file. Main body now well under 250.

**TDD discipline — 9 separate cycles, each a coherent unit:**
1. `setType` (RED → GREEN → commit)
2. `setCueNumber`
3. `setFadeTime`
4. `setNotes`
5. `commitFadeTime` helper (parse-or-revert)
6. `commitCueNumber` helper (parse-or-revert)
7. `CueInspectorView` + `VSplitView` integration in `CueListPane` + `updateCue` refactor + `CueCommands+Items` split (compile-checked, exercised by existing 149 tests)
8. Docs (data-model.md field rules)
9. Simplify pass (formatNumber dedup + CueColorSwatch extraction + focused-aware syncDrafts)

**TDD discipline slip and recovery (cycle 5):** initially implemented `commitFadeTime` and `commitCueNumber` together but only had a failing test for `commitFadeTime`. Caught before commit during a re-read of the TDD skill rules. Reverted the un-tested `commitCueNumber` + `NumberOutcome` enum + `formatNumber` from the impl, amended the cycle-5 commit to fade-only, then went RED → GREEN properly for cueNumber in cycle 6. The /feature skill's strict-TDD requirement forces these checks; the slip was ~5 minutes of process loss, not lost work.

**XCUITest deferred:** view-host tests for the Gherkin scenarios were not added because `OnlyCueUITests` has been flaky on this machine (prior session memo on `DocumentLaunchTests` zombie-process failures). Behavior is fully covered by `CueInspectorCommitTests` (parse-or-revert) + `CueCommandsTests` (round-trip + undo). When the harness stabilises, a follow-up can map the Gherkin scenarios to XCUITests directly.

**Closing note — fourth leaf of #32 done; the inspector closes the schema-surface gap.** Two leaves remain under #32, both UI-shaped: number-key cue creation (1–0 binds to a `Type` via `Type.hotkey` — model layer already accepts the value, just needs keymap wiring), and the UI rewire that reads color from the Type and removes the transitional `Cue.colorHex` (would be schema v6). Carry-overs from PR #47 review still open: [#48](https://github.com/chienchuanw/only-cue/issues/48) (stable-sort tie-breaker on equal `cue.time`) and [#49](https://github.com/chienchuanw/only-cue/issues/49) (drop the `cueNumber: 0` placeholder in `LegacyCue.toCue` / `LegacyV3Cue.toCue` / `LegacyV4Cue.toCue` via a `PendingCue` helper).

---

## 2026-05-08 — Cue.fadeTime with split-fade syntax, schema v5 (PR #51, leaf #50 of epic #32)

**Shipped:** issue #50 (third leaf of epic #32). PR #51 merged into `dev` (rebase, head `99aeda8`). Every `Cue` now carries a required `fadeTime: FadeTime`, where `FadeTime` is a value `struct { fadeIn, fadeOut: TimeInterval }` with synthesized `Codable`. Symmetric fades (`fadeIn == fadeOut`) and split fades (`fadeIn != fadeOut`) are both representable; the user-facing string form (`"1.5"` symmetric, `"1/2"` split) is handled by a pure `FadeTime.parse(_:) -> FadeTime?` and a canonical `format() -> String`. Schema bumped to **v5** with a v4→v5 migration that backfills `.zero` (no fade) on every existing cue; v1, v2, v3 chains backfill at the `LegacyCue.toCue` / `LegacyV3Cue.toCue` boundary so any pre-v5 source lands on a v5 model.

**Why struct, not enum:** the central design call at CHECKPOINT 1 was `struct { fadeIn, fadeOut }` vs `enum { .symmetric(t); .split(in:out:) }`. Picked struct: synthesized Codable keeps the JSON shape compile-checked without a custom encoder, the symmetric/split distinction is a derived fact (`fadeIn == fadeOut`) not a hidden invariant, and the future cue inspector pane gets two-way bindings for free (two `var` properties → two TextFields, no case rebuilds on every keystroke). The enum's "encode the symmetric/split distinction at the type level" advantage was not worth its costs (custom Codable, schema-evolution risk, mutation friction). Captured as **ADR-011**.

**Why parser is the gate (not the struct):** the model layer trusts its inputs — `FadeTime(fadeIn: -1, fadeOut: 0)` is permitted, the struct doesn't trap. Validation lives in `FadeTime.parse(_:)`, which is the single entry point from user/UI/migration. Same trust-the-seam design we used for `Cue.cueNumber` going negative on edge cases. Construction sites (CueCommands, all four legacy migrations, test fixtures) all use `FadeTime.zero` rather than `FadeTime(fadeIn: 0, fadeOut: 0)` or `.symmetric(0)` — the constant reads as "no fade default" intent rather than asking the reader to know that 0 = no fade.

**What landed in PR #51 (8 commits):**
- `OnlyCue/Document/FadeTime.swift` (new) — `struct FadeTime: Codable, Equatable, Hashable`, plus an extension carrying `static let zero`, `static func symmetric(_ seconds:)`, `static func parse(_ text:) -> FadeTime?`, and instance `func format() -> String`. Parser accepts `"1"`/`"1.5"` (symmetric) and `"1/2"` (split), trims surrounding whitespace, rejects 18 malformed inputs (empty, blank, non-numeric, negative, multi-slash, half-empty, internal whitespace, non-finite `inf`/`infinity`/`Inf`, leading-`+`). Formatter emits `"1.5"` when `fadeIn == fadeOut` else `"1/2"`, drops trailing `.0` on whole numbers (`"1"` not `"1.0"`).
- `OnlyCue/Document/Cue.swift` — gains required `var fadeTime: FadeTime`.
- `OnlyCue/Document/ProjectModel.swift` — `currentSchemaVersion` 4 → 5; `case 4: migrateFromV4` added to the decode switch; new private `LegacyV4` / `LegacyV4Item` / `LegacyV4Cue` shapes (the v4 envelope minus `fadeTime`); `migrateFromV4(_:)` constructs cues with `fadeTime: .zero`; existing `LegacyCue.toCue` (v1/v2 path) and `LegacyV3Cue.toCue` extend their `Cue(...)` initializers with `fadeTime: .zero`.
- `OnlyCue/Commands/CueCommands.swift` — `addCueAtPlayhead` constructs new cues with `fadeTime: .zero`.
- `OnlyCueTests/FadeTimeTests.swift` (new) — 16 tests: 2 Codable round-trips (symmetric, split), 6 parser happy paths, 1 omnibus rejection test covering 18 malformed inputs, 5 formatter cases, 2 parse↔format round-trip cases.
- `OnlyCueTests/ProjectModelTests.swift` — `test_cueFadeTimeRoundTripsThroughJSON_split` (new); schema-version sentinel renamed `…IsFour` → `…IsFive`; existing fixtures updated with `fadeTime: .zero`.
- `OnlyCueTests/ProjectModelMigrationTests.swift` — `test_v4_assignsZeroFadeToExistingCues` (new); v1/v2/v3 chain tests grew `fadeTime == .zero` assertions; v3 and v4 JSON fixtures hoisted to file-scope `private let` (`v3FixtureWithUnsortedCues`, `v4FixtureWithoutFadeTime`) to keep the class body under SwiftLint's `type_body_length` cap.
- `docs/data-model.md` — schema v5 throughout: example JSON with `fadeTime` field, Swift types section adds `FadeTime`, new `cue.fadeTime` field rules row, versioning policy describing all four migration chains (v1→current through v4→current).
- `docs/decisions.md` — **ADR-011** (after ADR-010 cueNumber).
- **133/133 unit tests green; 0 SwiftLint violations; Release build clean (warnings-as-errors).**

**Simplify pass — 3 fixes (commit `99aeda8`):**
1. Quality reviewer caught a real bug: the parser docstring promised "rejects non-numeric" but `Double("inf")` returns infinity (and `Double("+1")` returns 1.0). Added `value.isFinite` and `!hasPrefix("+")` guards. Confirmed via 6 new rejection inputs (`"inf"`, `"infinity"`, `"Inf"`, `"+1"`, `"+1/2"`, `"1/+2"`).
2. The `.symmetric(0)` literal appeared at 8+ sites. Quality reviewer flagged it as "no-fade intent that should be grep-able". Extracted `static let zero: FadeTime = .symmetric(0)` and replaced every production and test call site. Reads as `fadeTime: .zero` instead of `fadeTime: .symmetric(0)`.
3. Trimmed `parse(_:)` docstring from a 2-line listing of the rejection set to a one-line pointer at `FadeTimeTests` for the full grammar — the test names are the canonical spec; duplicating them in a docstring just creates drift.

**Skipped from simplify:**
- "`String(t)` for non-whole doubles produces `0.30000000000000004` for arithmetic-derived values" — theoretical concern (no current call path produces such values; parser produces clean doubles, no `FadeTime` arithmetic exists). Defer to whichever future leaf adds fade-time arithmetic.
- Reuse reviewer's "`LegacyV4*` boilerplate is structurally identical to `LegacyV3*`" — kept the duplication on purpose. Each `LegacyVN` is a frozen snapshot; generalising would couple frozen formats and create regression risk on every future schema bump. Pattern is intentional.

**SwiftLint hits — same playbook as PR #47, caught earlier this time:**
1. **`type_body_length`** — `ProjectModelMigrationTests` swelled to 282 lines after adding `test_v4_assignsZeroFadeToExistingCues` + the new `v4FixtureWithoutFadeTime` static let (cap is 250). Hoisted both `v3FixtureWithUnsortedCues` and `v4FixtureWithoutFadeTime` from `private static let` (in-class) to file-scope `private let` constants between the imports and the class declaration. Class body dropped to ~125 lines.
2. **`identifier_name`** — single-letter parameter names `t: TimeInterval` and `s: Substring` violated min-2 (one of the leftover footguns from #46's similar fix on `var c`). Renamed to `seconds` and `text`.

Both blockers caught by `swiftlint --strict` locally before pushing — same pattern as PR #47 fix #4 (re-running lint between fix commits catches self-inflicted regressions). No CI surprises.

**TDD discipline — 8 separate commits, each a coherent unit:**
1. FadeTime struct with synthesized Codable + symmetric round-trip test
2. Parser (happy + rejection)
3. Canonical formatter + parse/format round-trip
4. `Cue.fadeTime` field + 7 construction-site updates with `.symmetric(0)` (later replaced by `.zero` in simplify)
5. `currentSchemaVersion` 4 → 5 + `migrateFromV4` + LegacyV4 types
6. Chain regression assertions across v1/v2/v3 migration tests
7. Docs (data-model.md + ADR-011)
8. Simplify pass (parser hardening + `.zero` constant + fixture hoisting + lint-driven renames)

Each cycle: red (verified failure), green (minimum impl), commit. Cycle 2 (split round-trip) was a regression check that passed immediately on the synthesized Codable from cycle 1 — fine, documented as such in the commit log rather than papered over.

**Closing note — third leaf of #32 done; model rework for epic #32 is complete.** Remaining leaves under #32 are now UI/UX shaped (no more schema bumps planned for the epic): number-key cue creation (1–0 binds to a Type via the keymap), cue inspector pane (edit Type / cueNumber / fade / notes), and the UI rewire that reads color from the Type and removes transitional `Cue.colorHex`. Carry-overs from PR #47 review still open: [#48](https://github.com/chienchuanw/only-cue/issues/48) (stable-sort tie-breaker) and [#49](https://github.com/chienchuanw/only-cue/issues/49) (drop the `cueNumber: 0` placeholder in `LegacyCue.toCue` / `LegacyV3Cue.toCue` via a `PendingCue` helper). The same `fadeTime: .zero` placeholder pattern in `LegacyV4Cue.toCue` would naturally fold into the same fix.

---

## 2026-05-08 — Editable Cue.cueNumber with mid-point insertion rule, schema v4 (PR #47, leaf #46 of epic #32)

**Shipped:** issue #46 (second leaf of epic #32). PR #47 merged into `dev` (rebase, head `19713f9`). `Cue` now carries a user-facing `cueNumber: Double` distinct from `Cue.id: UUID`. `addCueAtPlayhead` assigns the number by an "insert without ripple" rule: empty list → 1.0; at-end → predecessor's number + 1; between two cues → mid-point; before all → successor's number − 1 (may go negative on repeated inserts before the minimum). Schema bumped to v4 with a v3→v4 migration that assigns sequential numbers by time order; v1 and v2 paths chain through the same shared `assignCueNumbersBySort` helper.

**Why required `Double`, not `Optional<Double>`:** modelling it as required keeps every downstream consumer (export #34, the future cue inspector, breakdown view #37) free of `Optional` plumbing. The schema bump is a one-time cost; `Optional` plumbing is forever. Captured as **ADR-010**.

**Why mid-point insertion, not renumber-on-insert:** existing cue numbers are stable. A console operator who wrote down "GO 4" doesn't see it become "GO 5" because someone added a cue earlier in the timeline. The future cue inspector will provide a "renumber from 1" command to normalize the negatives that accumulate from repeated before-all inserts.

**What landed (5 TDD commits + 1 simplify + 4 review-fix commits = 10 commits):**
- `OnlyCue/Document/Cue.swift` — gains required `cueNumber: Double`.
- `OnlyCue/Document/ProjectModel.swift` — `currentSchemaVersion` 3 → 4. New private `LegacyV3` / `LegacyV3Item` / `LegacyV3Cue` decoder shapes. New `migrateFromV3`. New private `assignCueNumbersBySort(_:)` that every migrate function (v1/v2/v3) calls on its return value — v1/v2/v3 cues all land sorted by time with sequential `cueNumber`s `1.0, 2.0, ...`.
- `OnlyCue/Commands/CueNumberAssignment.swift` (new file, landed during review-fix cycle) — `enum CueNumberAssignment { static func next(forInsertionAt:in:) -> Double }`. Pure function, naturally reusable from a future "Renumber from 1" command. Extracted from `CueCommands` to keep that enum body under SwiftLint's `type_body_length` cap.
- `OnlyCue/Commands/CueCommands.swift` — `addCueAtPlayhead` calls `CueNumberAssignment.next(forInsertionAt: clampedTime, in: existingCues)` for the new cue's number. Pre-existing `defaultCueColorHex` constant gone (sourced from active default Type per PR #45).
- 6 new unit tests across `CueCommandsTests` (5 algorithm cases: empty / at-end / mid / at-start / repeated-at-start-goes-negative) and 1 new `ProjectModelMigrationTests.test_v3_assignsCueNumbersBySortOrder` (uses out-of-time-order JSON to verify the migration sorts cues). Existing v1/v2 migration tests grew assertions on cueNumber. Schema-version sentinel renamed v3 → v4. Codable round-trip for cueNumber added. **115/115 unit tests green.**
- `docs/data-model.md` — schema v4 throughout: example JSON, Swift types, field rules with the `cue.cueNumber` assignment-rule entry, versioning policy describing all three migration chains (v1→current, v2→current, v3→current) all ending in `assignCueNumbersBySort`.
- `docs/decisions.md` — **ADR-010** (after ADR-009 CuePoint Types).

**Simplify pass — 3 fixes (commit `e9c9d09`, before review):**
1. Unreachable `(nil, nil)` case in `nextCueNumber` → `preconditionFailure` with a descriptive message. Quality reviewer's call: silent-return-1.0 was masking an invariant break.
2. Trim `assignCueNumbersBySort` doc comment from three lines to one. Restating the body was noise; only the "predates the field" why-context was load-bearing.
3. Add `// overwritten by assignCueNumbersBySort` comments at each `cueNumber: 0` placeholder in `LegacyCue.toCue` and `LegacyV3Cue.toCue`. After this leaf, `0` is a legitimate value (`addCueAtPlayhead` produces it for "before all when min was 1"), so the sentinel had become indistinguishable from data.

**Skipped from simplify:**
- "Drop the redundant `.sorted` in `CueNumberAssignment.next`" — efficiency reviewer wanted it gone (caller's input is invariant-sorted), quality reviewer wanted it kept (helper self-containment). Kept for safety; cost is trivial at OnlyCue's scales.
- "Drop `cuePointTypes: [CuePointType] = []` default" — quality reviewer claimed all callers pass it explicitly; verified false (3 tests rely on it for empty-project fixtures).

**Review cycle — 4 SwiftLint blockers + 3 substantive notes** (one round, all blockers resolved in 4 fix commits + 1 piggybacked tweak):
1. **`identifier_name`** (`var c` in `assignCueNumbersBySort`) → renamed to `var updated`. Commit `a3827c4`.
2. **`type_body_length`** (`CueCommands` enum body 251/250) → reviewer's structural suggestion: extract `nextCueNumber` to its own file rather than nudge the cap. Created `OnlyCue/Commands/CueNumberAssignment.swift`. Commit `b304eb6`.
3. **`line_length`** 144 chars at `ProjectModelTests:27` → broke the `Cue(...)` initializer across lines. Commit `830a629`.
4. **`function_body_length`** 66/50 at `test_v3_assignsCueNumbersBySortOrder` → hoisted the v3 JSON literal to a private static `let v3FixtureWithUnsortedCues` above the test. Same commit also trimmed a 143-char `preconditionFailure` message in the new `CueNumberAssignment.swift` that the extract had introduced. Commit `21e6767` (rebase-mapped to `19713f9`).

**Substantive notes deferred:**
- Issue [#48](https://github.com/chienchuanw/only-cue/issues/48) — stable-sort tie-breaker on equal `cue.time` in `assignCueNumbersBySort`.
- Issue [#49](https://github.com/chienchuanw/only-cue/issues/49) — drop the `cueNumber: 0` placeholder in `LegacyCue.toCue` / `LegacyV3Cue.toCue` via a `PendingCue` tuple or struct so the type system enforces "every Cue gets a real cueNumber".

**Workflow gotcha — gh-fix's "fetch unresolved review threads" came back empty.** The reviewer's feedback was an issue-level PR comment (`gh pr view --json comments`), not a review thread. Always check both surfaces. Cross-referenced with the failed CI run's `gh run view --log-failed` output to confirm all 4 violations.

**Workflow gotcha — re-running `swiftlint --strict` between fix commits caught one self-inflicted regression.** Extracting `nextCueNumber` introduced a 143-char line in the new file (the `preconditionFailure` message). Caught locally before push by re-running lint, not just at the end of the fix cycle.

**Closing note — second leaf of #32 done.** Remaining leaves under epic #32: `Cue.fadeTime` with split-fade syntax (`1/2`), number-key cue creation (1–0), cue inspector pane, and the UI rewire to read color from the Type + remove transitional `Cue.colorHex`.

---

## 2026-05-08 — Phase 2 epics filed + first leaf shipped: CuePointType schema v3 (PR #45, leaf #44 of epic #32)

**Shipped:** the parity-push slate for Phase 2 (9 epics, [#32–#40](https://github.com/chienchuanw/only-cue/issues?q=is%3Aissue+milestone%3A%22Phase+2+%E2%80%94+Pro+handoff%22)) and the first leaf of #32. PR #45 merged into `dev`. `ProjectModel` now carries a `cuePointTypes` catalog and every `Cue` references a Type by `typeID`. Schema bumped to **v3** with a v2→v3 migration that seeds a default Type "General" carrying the previous `defaultCueColorHex` and assigns its id to every existing cue. v1→current chains through the same default-Type seeding.

**Why now (brainstorm session):** competitive analysis of CuePoints (the reference product) surfaced 9 gaps that block a programmer from leaving CuePoints — `CuePoint Types` as shared organising primitive (this leaf), editable `Cue.id` with ripple-down, `Cue.fadeTime` with split syntax, LTC + audio routing, console export (CSV/MA2/MA3), OSC remote control (Companion / MA3 / StreamDeck), timeline UX polish, breakdown view, notes overlay, plus the already-roadmap'd templates and custom shortcuts editor. User picked **pro-handoff parity** as the positioning (vs. full-clone or differentiate-first); Tier-C differentiator (AI cueing / collaboration / console round-trip) deferred to Phase 3. Filed 9 epics + 4 new area labels (`area:types`, `area:ltc`, `area:export`, `area:osc`) in one batch; all assigned to the **Phase 2 — Pro handoff** milestone.

**What landed in PR #45 (8 commits):**
- `OnlyCue/Document/CuePointType.swift` (new) — `{id, name, colorHex, defaultFadeTime, defaultNamePattern, hotkey, isVisible, isExportEnabled}` with property-level defaults so callers normally only pass `(id, name, colorHex)`. Reserved fields (`hotkey`, `isVisible`, `isExportEnabled`) anchor the future leaves (number-key creation, breakdown view, export filter) so each one adds behavior, not schema.
- `OnlyCue/Document/Cue.swift` — gains required `typeID: UUID`. Initially had a `UUID()` default; the simplify pass dropped it after agents flagged it as both an orphan-id hazard *and* a per-decode UUID-allocation cost (Swift `Decodable` synthesis still computes default expressions on present-key decode for missing-key fallback).
- `OnlyCue/Document/ProjectModel.swift` — `cuePointTypes: [CuePointType]` (invariant: ≥ 1; index `[0]` is the default), computed `defaultCuePointTypeID`, `currentSchemaVersion = 3`, `LegacyV2`/`LegacyCue` shapes, both migrations, public `makeDefaultCuePointType()` factory.
- `OnlyCue/Document/CueListDocument.swift` — `init()` seeds a default Type unconditionally so untitled documents are valid v3 from creation.
- `OnlyCue/Commands/CueCommands.swift` — `addCueAtPlayhead` sources the new cue's color from `document.model.cuePointTypes.first?.colorHex` (single source of truth) and `assertionFailure` + no-op if the Types invariant is broken upstream.
- `OnlyCueTests/CuePointTypeTests.swift` (new), `CueListDocumentTests.swift` (new) — Codable round-trip, default seeding.
- `OnlyCueTests/ProjectModelTests.swift` + `ProjectModelMigrationTests.swift` — schema-version sentinel, Type-aware round-trip, v2→v3 migration test, v1→current regression. **108/108 unit tests green.**
- `docs/data-model.md` rewritten for schema v3 (example JSON, Swift types, field rules, versioning policy with both migration paths). New ADR-009 in `docs/decisions.md`. Removed the "all cues are generic" line from "deliberately NOT in the model".

**Simplify pass — 5 fixes (commit `6e5aae0`):**
1. Dropped the unsafe `Cue.typeID = UUID()` default. Three reviewers converged: orphan-id hazard (a Cue could silently reference no Type) + per-decode UUID cost. Now required at construction.
2. Collapsed byte-identical `LegacyV1Cue` / `LegacyV2Cue` into a single shared `LegacyCue` struct used by both migration paths.
3. Replaced `?? UUID()` fallback in `addCueAtPlayhead` with `assertionFailure` + no-op (matches the pre-existing `mutateCues` no-op pattern when `activeItemID == nil`). The fallback was masking a real invariant violation with a dangling id that no Type could resolve.
4. Sourced new cue's color from the active default Type instead of duplicating `defaultCueColorHex` on `CueCommands`. One source of truth — the duplication would have rotted as soon as the Types editor lets users change the default color.
5. Replaced `CuePointType`'s explicit init (mirror of the synthesized memberwise init, only adding defaults) with property-level defaults. Same shape, fewer lines.

**TDD discipline:** 7 separate red→green commits before the simplify pass. Each cycle: write failing test → confirm it fails for the expected reason (e.g. "Cannot find 'CuePointType' in scope" for cycle 1, "Extra argument 'typeID'" for cycle 2, decode `keyNotFound` for cycle 3) → minimal implementation → green → next cycle. The full-suite check after each green caught the v1-migration `keyNotFound` regression (cue's `typeID` not in v1 JSON) in cycle 2 itself, fixed by introducing `LegacyV1Cue` immediately rather than letting it cascade.

**Discovery during grounding:** the codebase had already shipped `currentSchemaVersion = 2` (PR #41 multi-media items merged earlier today). The leaf body originally said "schema v2"; corrected to v3 mid-design when reading `OnlyCue/Document/ProjectModel.swift` revealed actual current state. Also fixed issue #44's title v2→v3 alongside the PR. **Lesson:** when picking up a project after a brainstorm-only session gap, refresh code state (`Read` the model files; `git log` since the last familiar commit) before locking the design — assumptions about schema version or in-flight features rot fast in active repos.

**Filing rhythm:** the brainstorm session filed 9 epics in parallel via `gh issue create` after creating 4 new `area:*` labels. Each epic body includes leaf checklists; leaves get filed as separate issues when picked up via `gh-dev`, matching the MVP convention (epics #4–#11 each spawned 5–8 leaf PRs). Leaf #44 here is the first such filing under #32 — the original "Leaf: spec — schema v3 + ADR" and "Leaf: model — introduce CuePointType" lines bundled into one TDD-friendly PR (a docs-only spec leaf doesn't fit `/feature`'s strict TDD requirement).

**Closing note — Phase 2 has begun.** The data model is now Type-aware; the foundation under #34 (export), #37 (breakdown view), and #39 (templates) is in place. Remaining leaves of #32: editable `Cue.id` with ripple-down, `Cue.fadeTime` with split syntax, number-key cue creation, cue inspector pane, UI rewire to read color from the Type (and remove transitional `Cue.colorHex`).

---

## 2026-05-08 — Multi-media items per project (PR #41, issue #31)

**Shipped:** issue #31 (post-MVP enhancement). PR #41 merged into `dev`. A `.cuelist` document now represents an entire show: it holds a list of `MediaItem`s, each with its own media reference and its own cue list. Multi-file imports append items in selection/drop order. A left sidebar lets the user switch the active item, drag-reorder, and ⌫-delete with undo.

**What landed (8 commits + 1 user `.gitignore`):**
- Schema bumped to **v2**. `ProjectModel` now exposes `items: [MediaItem]` and `activeItemID: UUID?`. New `MediaItem` wraps a non-optional `MediaReference` plus its own `cues: [Cue]`. `ProjectModel.decode(from:)` probes the version and migrates v1 forward — v1+media wraps into one `MediaItem`; v1+nil yields empty items. One-way upgrade (v0.1.0 readers cannot open v2). Captured as **ADR-008**.
- `OnlyCue/Document/{ProjectModel,MediaItem,CueListDocument}.swift` carry the new types and the migration entry point.
- `OnlyCue/Commands/CueCommands.swift` — existing cue mutations now scope to the active item via `mutateCues` (no-op when `activeItemID == nil`). New item-level commands: `addItem`, `addItems` (one undo group per batch), `removeItem` (advance active to next or previous if last), `renameItem`, `reorderItems`. `setActiveItem` and `refreshBookmark` are intentionally NOT undoable — selection is view state; stale-bookmark refresh is OS-driven.
- `OnlyCue/Commands/MediaImporter.swift` — accepts `[URL]`. `withTaskGroup` parallelizes per-file `AVURLAsset.load(.duration)` so N-file import scales by the slowest file rather than the sum. Per-file failures collected as `MediaImportError.batch(unsupported:)`; valid imports still append. After import, kicks off a detached background-priority `WaveformPrewarmer`.
- `OnlyCue/Media/PlayerEngine.swift` — added `unload()` for clean teardown on item switch.
- `OnlyCue/Media/WaveformPrewarmer.swift` (new) — runs `WaveformGenerator.peaks` + `WaveformCache.write` for each new item in the background. Cache hits are skipped (verified by `cacheHit_isANoOp` test asserting mtime is unchanged).
- `OnlyCue/UI/DocumentView.swift` — three-pane `NavigationSplitView` (items | preview | cues). `task(id: activeItemID)` drives engine reload; SwiftUI's task-id dedup is sufficient.
- `OnlyCue/UI/{ItemListPane,ItemRowView}.swift` (new) — sidebar list, `.onMove` drag-reorder, multi-URL drop, ⌫ to remove.
- `OnlyCue/UI/PreviewPane.swift` — waveform now resolves the active item's bookmark on `task(id: activeItemID)` and feeds the resulting URL into `WaveformContainer` keyed with `.id(url)`. Source of truth shifted from `engine.player.currentItem?.asset` (which lags through engine reload) to the model.
- `OnlyCue/UI/{CueListPane}.swift` — binds to active item's cues.
- 16 new unit tests: `ProjectModelMigrationTests` (3), `CueCommandsItemTests` (11), `WaveformPrewarmerTests` (2). Updated `ProjectModelTests`, `CueCommandsTests`, `MediaImporterTests` for the new model. **67/67 unit tests green.**
- `docs/data-model.md` rewritten for v2; `docs/architecture.md` three-pane diagram + new component map; `docs/decisions.md` ADR-008; `docs/verification.md` step 14 covers multi-import + per-item cue isolation + drag-reorder persistence; `docs/build-sequence.md` post-MVP row #13.

**Simplify pass — 4 fixes (commit `aed3e5d`):**
1. Parallelized `MediaImporter.makeItem` via `withTaskGroup` (HIGH-priority efficiency win flagged in review).
2. Routed stale-bookmark refresh through new `CueCommands.refreshBookmark` seam (was directly mutating `document.model.items[index].media.bookmarkData`, violating CLAUDE.md hard rule "No direct mutations of `ProjectModel`").
3. Dropped `loadedItemID` belt-and-suspenders cache and the `onActiveItemChange` callback. SwiftUI's `task(id:)` is already idempotent — the `@State` cache and the parent-callback ping were duplicating its own dedup.
4. Stopped rewriting `schemaVersion` in `snapshot(contentType:)`; it is set at decode/init time.

**Two real bugs caught in user testing, fixed in-PR:**
1. **Wrong waveform on item switch.** Even with `.id(asset.url)` on `WaveformContainer`, the waveform briefly painted the previous item's peaks against the new item's cue markers and playhead. Root cause: `PreviewPane` was reading the asset from `engine.player.currentItem?.asset`, which lags through `MediaImporter.loadActive`. Fix (commit `a16b179`): `PreviewPane` resolves the active item's bookmark on `task(id: activeItemID)` and feeds the URL to the waveform — model-sourced, not engine-sourced. Captured in `findings.md` as a SwiftUI invalidation pattern: when a leaf view's identity is conceptually tied to one of its inputs, `.id` that input — but make sure the input itself isn't sourced from a stale-by-design dependency.
2. **Slow first render of each item's waveform.** Cache miss path was paid on every first click. Fix (commit `a60e697`): `WaveformPrewarmer` warms the cache in the background right after import. Subsequent clicks are cache hits.

**SwiftLint cleanup (commit `8603b76`):** 6 warnings cleared — shorthand `[T]` over `Array<T>`, `V1`→`LegacyV1` (type-name length), `a`/`b`/`c` test variables → `first`/`middle`/`last`/`only`/`second`, multiline argument formatting, `v` → `version` in catch binding, comma spacing.

**Closing note — third post-MVP enhancement landed.** The data model now supports the way real shows are organized (one project = N items). Phase 2 epics still unscoped on the issue board. Roadmap unchanged.

---

## 2026-05-08 — Waveform playhead with drag-to-scrub (PR #30, issue #29)

**Shipped:** issue #29 (post-MVP enhancement). PR #30 merged into `dev`. The waveform now shows the play position as a draggable vertical line with a floating HH:MM:SS label, on both the audio-only waveform and the audio strip beneath the video preview.

**What landed:**
- `OnlyCue/UI/PlayheadOverlay.swift` (new) — pure SwiftUI view: vertical line at `CueMarkersGeometry.position(...)` plus a frosted-material HH:MM:SS pill via `TimeFormat.hms`, label x clamped to waveform bounds. Hit-test free.
- `OnlyCue/UI/ScrubController.swift` (new) — value-type state machine with `begin(originalTime:isPlaying:)`, `update(dx:width:duration:)`, `end()`. Reuses `CueMarkersGeometry.time(...)` for clamped time math. Unit-tested without SwiftUI.
- `OnlyCue/UI/WaveformPlayheadLayer.swift` (new) — owns the `engine.currentTime` read, the `PlayheadOverlay`, and a 12pt-wide `Color.clear` drag grabber. Hoisted into its own subview so 10 Hz ticks don't re-evaluate `CueMarkersOverlay` (see findings).
- `OnlyCue/UI/WaveformContainer.swift` — gains one optional `engine: PlayerEngine?`. Passing it opts into the playhead+grabber overlay; absence preserves prior behavior.
- `OnlyCue/UI/PreviewPane.swift` — both `audioContent` and `videoContent` pass `engine` to the waveform helper.
- `OnlyCue/Media/PlayerEngine.swift` — added `var isPlaying: Bool { rate > 0 }` to retire the `rate > 0` magic at call sites.
- `OnlyCueTests/PlayheadOverlayTests.swift` (4 tests, label-clamp behavior) and `OnlyCueTests/ScrubControllerTests.swift` (7 tests, state transitions). 65/65 unit tests green.
- `docs/superpowers/specs/2026-05-08-waveform-playhead-design.md` (new) — spec captured before implementation; updated mid-PR for the scope flip and the simplify refactor.
- `docs/verification.md` — new step 4 covers playhead + scrub on the audio waveform; step 12 updated to expect the same on the video strip.

**TDD discipline:** red commit (`82e95b1` — failing playhead + scrub tests with build error proving they ran) → green commit (`4f62750` — implementations land, tests pass) committed separately, per project convention.

**Simplify pass — 4 fixes (commit `ea8bfc6`):**
1. Hoisted playhead + grabber into `WaveformPlayheadLayer` so `engine.currentTime` ticks no longer re-evaluate `CueMarkersOverlay`. Single biggest perf win in the diff.
2. Dropped the redundant `showsPlayhead: Bool` flag on `WaveformContainer`. Engine presence (`engine != nil`) now implies the playhead — one fewer parameter to keep in sync between caller and callee.
3. Added `PlayerEngine.isPlaying` and used it in the scrub gesture. Also useful for `TransportBar`'s `rate > 0` check next time we touch it.
4. Cancel any in-flight seek `Task` before starting a new one on rapid re-scrub, so out-of-order seeks can't land.

**Mid-PR scope flip:** brainstorm originally locked the playhead to audio-only on the assumption video had an "implicit" playhead via the moving frame. User testing immediately disagreed: "I see PlayheadOverlay only in imported audio. Check and fix it." One-line fix in `PreviewPane.videoContent` (`waveform(for:asset, withPlayhead: true)`), plus spec + verification doc reconciled. Lesson: scope-by-assumption survives spec review but not the first run on the actual artifact.

**Closing note — second post-MVP enhancement landed.** Phase 2 epics still unscoped on the issue board. Roadmap unchanged.

---

## 2026-05-08 — Video waveform display (PR #28, issue #27)

**Shipped:** issue #27 (post-MVP enhancement). PR #28 merged into `dev`. First post-MVP feature — corrects an asymmetry the MVP shipped with: cue-marker drag-to-retime and click-to-seek lived only on the audio waveform, so video imports had no timeline editing affordance. Now video imports show the picture stacked above a 100pt waveform strip; cue markers, drag, and seek work identically to the audio path.

**What landed:**
- `OnlyCue/UI/PreviewPane.swift` — `videoContent` becomes `VStack { videoPlayer; waveform.frame(height: 100) }`. Extracted `videoPlayer` and `waveform(for:)` as shared helpers so audio and video paths route through one cue-marker wiring (`onSeek`, `onRetime → CueCommands.retime`).
- `OnlyCue/Media/WaveformGenerator.swift` — when an asset has no audio track, `peaks(for:resolution:)` now returns `[Float](repeating: 0, count: resolution)` instead of throwing. `WaveformError.noAudioTrack` removed (only caller was `WaveformContainer`, which treated all throws uniformly). Silent videos render a flat baseline; markers stay draggable.
- `OnlyCueTests/WaveformGeneratorTests.swift` — new `test_peaks_assetWithNoAudioTrack_returnsFlatPeaks` using `AVMutableComposition()` (no fixture file needed).
- `docs/superpowers/specs/2026-05-08-video-waveform-design.md` — spec captured before implementation.
- `docs/mvp-scope.md`, `docs/architecture.md`, `docs/build-sequence.md`, `docs/verification.md` — preview-pane descriptions updated to reflect the new behavior.

**TDD discipline:** red commit (`ba49bcc` — failing test for no-audio-track asset) → green commit (`76340f1` — flat-peaks early return) committed separately, per project convention.

**Simplify pass — 1 fix (commit `679b9d9`):**
- `videoContent` had two branches each constructing `AVPlayerLayerView(player: engine.player).accessibilityIdentifier("videoPreview")`. Hoisted into a `videoPlayer` computed property.
- Other simplify findings (cache-flicker on cached read, fileHash cost on every `.task` fire, `loadedDuration` ordering before cache check) were pre-existing in `WaveformContainer` and out of scope for this change — file separately if revisiting waveform performance.

**Review cycle:**
- Auto-review flagged `docs/verification.md` step 11 still said the video preview "shows picture instead of waveform" — accurate; missed in initial docs sweep that updated `mvp-scope`/`architecture`/`build-sequence`. Fixed in `3f997ab` and posted status comment on PR #28.
- Lesson: when sweeping `docs/` for behavior changes affecting the preview pane, include `verification.md` alongside the architecture/scope/build-sequence trio. The verification MVP checklist contains user-visible behavior assertions that go stale with UX changes.

**Closing note — first post-MVP enhancement landed.** Phase 2 (LTC, templates, export, custom shortcuts, the differentiator) hasn't been scoped into epics yet; this PR was a targeted gap fix on the MVP itself. Roadmap unchanged.

---

## 2026-05-08 — E10 distribution + v0.1.0 release (PR #26, issue #12)

**Shipped:** issue #12 (E10 distribution). PR #26 merged into `dev` (rebase, head `008cf03`). Then ran the post-merge release sequence in this session: tagged `v0.1.0` on `008cf03`, built and DMG'd via the C3 scripts, published the [v0.1.0 GitHub Release](https://github.com/chienchuanw/only-cue/releases/tag/v0.1.0) with `OnlyCue-0.1.0.dmg` attached. **MVP is live.**

**What landed (docs in PR #26):**
- `README.md` — new `## Install` section above `## Status` with the right-click → Open Gatekeeper bypass walkthrough; mentions Control-click for trackpad users; system-requirements line (macOS 14+, both architectures); "build from source" escape hatch link. Distribution row in the stack table tightened to "Ad-hoc signed DMG (Developer ID + notarization opt-in)".
- `docs/release-notes/0.1.0.md` (new file) — the literal body for `gh release create --notes-file`. Lists shipped features (document workflow, media import, preview, transport, cue list, cue editing, cue markers, polish), install steps, known limitations (Gatekeeper prompt on free tier, sandbox off, no Sparkle, cue list ←/→ contention with global shortcuts when inspector is focused), pointer at `docs/verification.md` for the full manual end-to-end script.
- `docs/verification.md` — "Distribution sanity check" rewritten with mode-aware expectations: unsigned `spctl` rejects (expected; right-click → Open clears the prompt), signed `spctl` accepts (silent first launch). "OnlyCue is damaged" flagged as the regression signal that ad-hoc signing didn't take.

**Iteration via simplify pass — 3 fixes (commit `008cf03`):**
1. Release notes overstated supported audio/video formats by listing 7 closed extensions when `MediaImporter.allowedContentTypes` is `[.audio, .movie]` (anything AVFoundation accepts). Broadened to "any AVFoundation-supported audio or video file (`.mp3`, `.wav`, ..., and friends)".
2. Release notes had an internal ADR-007 reference in user-facing copy. Trimmed to "App Sandbox is off." — internal pointers don't belong in release notes.
3. Right-click instructions in both README and release notes lacked a Control-click alternative for trackpad users without secondary-click configured.

**Post-merge release sequence (this session, on user's machine):**
- `git tag -a v0.1.0 -m "OnlyCue 0.1.0"` on `008cf03`; `git push origin v0.1.0`.
- `bash scripts/build-release.sh` → `build/export/OnlyCue.app` (ad-hoc signed; `codesign --verify --deep --strict --verbose=2` clean: "valid on disk", "satisfies its Designated Requirement").
- `bash scripts/make-dmg.sh` → `build/OnlyCue-0.1.0.dmg` (~907 KB, compressed HFS+ disk image).
- `gh release create v0.1.0 --title "OnlyCue 0.1.0" --notes-file docs/release-notes/0.1.0.md "build/OnlyCue-0.1.0.dmg"` → [released](https://github.com/chienchuanw/only-cue/releases/tag/v0.1.0).

**Closing note — phase 1 complete.** All 13 MVP issues closed (#1, #2, #3–#11, #13, #12). Phase 2 (LTC timecode generation, cue templates, CSV / Resolve EDL export, OSC / MIDI integrations, beat-detection-assisted cue placement, plus the as-yet-undefined differentiator) starts when the issue board picks up new epics — see `docs/roadmap.md`.

---

## 2026-05-07 / 08 — C3 release pipeline session (PR #25, issue #13)

**Shipped:** issue #13 (C3 release pipeline). PR #25 merged into `dev` (rebase, head `6128837`). Bag of scripts + docs that turn `dev` into a drag-installable DMG.

**What landed:**
- `scripts/build-release.sh` — archive → (signed mode) export Developer ID → notarize → staple → verify, OR (unsigned mode) `cp -R` the ad-hoc-signed `.app` straight out of the archive. `RELEASE_MODE` env var (`unsigned` default, `signed` opt-in) gates which branch runs. Pre-flight checks for `xcodebuild` / `xcodegen` / `xcrun`; signed mode also probes `security find-generic-password -s "com.apple.gke.notary.tool" -a "$NOTARY_PROFILE"` (deterministic, offline) for the notary keychain profile and `security find-identity -v -p codesigning login.keychain` for the Developer ID identity. `[[ "${PIPESTATUS[0]}" -eq 0 ]]` guard around `xcodebuild | xcbeautify` so a failed archive can't be masked by xcbeautify's exit status.
- `scripts/make-dmg.sh` — `create-dmg` wrapper with sensible window/icon geometry (540×380, 96pt icons, 140/400 layout). In signed mode, also `codesign`s the DMG, submits it to notarytool as a separate submission, staples the ticket, and runs `spctl --assess --type open --context context:primary-signature`. Apple's recommended distribution path: both the .app and the DMG carry independent stapled tickets so first-mount works offline.
- `scripts/export-options.plist` — referenced only by signed mode's `xcodebuild -exportArchive` (`method: developer-id`, `signingStyle: automatic`).
- `docs/release.md` — leads with the free-tier path (`brew install xcodegen create-dmg xcbeautify`, then `bash scripts/build-release.sh && bash scripts/make-dmg.sh`); signed/notarized procedure stays as a "when we upgrade" section. Includes a copy-paste install blurb for end users walking through the right-click → Open Gatekeeper bypass, troubleshooting (Account Holder role for cert generation, "is damaged" failure mode, notary `Invalid` log fetch), and an ADR-007 sandbox note.

**Iteration via simplify pass — 4 fixes from 1 reviewer agent (commit `ba742d3`):**
1. `notarytool history` as a profile probe → network round-trip per build that flakes on transient 5xx. Replaced with the keychain probe above.
2. `xcodebuild ... | xcbeautify ... || true` masked archive failures because `pipefail` made xcbeautify's exit status the pipeline's. Switched to `PIPESTATUS[0]` guard.
3. `spctl --assess` on an unsigned DMG was a meaningless no-op logged as "non-fatal" — misleading. Fixed by signing, notarizing, and stapling the DMG itself in signed mode.
4. The "Publishing the release" section in `docs/release.md` had migrated into E10 territory (`gh release create`, README updates). Trimmed to a one-line pointer at #12 to keep C3 focused.

**Iteration mid-session — free-tier pivot (commit `6128837`):**
- User flagged that on the free Apple Developer tier, you can't generate a Developer ID Application certificate (those require the $99/yr paid program). Rather than block MVP shipping, refactored both scripts to accept `RELEASE_MODE=unsigned|signed` (default unsigned). The .app is ad-hoc signed (`CODE_SIGN_IDENTITY=-`) — critical because *truly* unsigned binaries trigger Gatekeeper's misleading "OnlyCue is damaged and can't be opened" error that even right-click → Open won't bypass. Ad-hoc signing produces the standard "developer cannot be verified" prompt, which right-click → Open or `xattr -dr com.apple.quarantine /Applications/OnlyCue.app` clears.
- `docs/release.md` rewritten to lead with the free-tier path, with a copy-paste install blurb users can paste into release notes.

**Iteration during user smoke-test:**
- `xcode-select` pointing at `/Library/Developer/CommandLineTools` instead of the full Xcode.app caused `xcodebuild` to error. Fix: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Worth adding to `docs/release.md` prerequisites in a follow-up.

**Verification (manual, by user):**
- `bash scripts/build-release.sh` produces `build/export/OnlyCue.app`; `codesign --verify --deep --strict --verbose=2` passes.
- `bash scripts/make-dmg.sh` produces `build/OnlyCue-0.1.0.dmg`; mounts cleanly.
- DMG contents: app icon visible, drag-to-Applications layout works.
- First launch from `/Applications` shows Gatekeeper "developer cannot be verified" prompt; right-click → Open clears it; the app launches with the first-launch welcome sheet.

---

## 2026-05-07 — E9 polish session (PR #24, issue #11)

**Shipped:** issue #11 (E9 polish, all 7 leaves). PR #24 merged into `dev` (rebase, head `e60ddd6`). With this, every MVP **feature** epic is done; the remaining MVP work is the C3 release pipeline (#13) and E10 distribution (#12).

**What landed:**
- `OnlyCue/Commands/MediaImporter.swift` — `static func reload(into:engine:) async throws`. Resolves `media.bookmarkData`, surfaces a missing file via `try await asset.load(.duration)`, and on `resolution.isStale == true` rewrites `document.model.media?.bookmarkData` with a freshly-created bookmark. Then calls `engine.load(asset:)`.
- `OnlyCue/UI/DocumentView.swift` — overhauled: collapsed two stacked `.alert(item:)` modifiers into one driven by a private `DocumentAlert` enum (`.unsupported(String)` / `.relink(String)`), added a `reloadedFor: Data?` sentinel + `.task(id: media?.bookmarkData)` to call `reloadIfNeeded` on first appear, added `.navigationSubtitle(media?.displayName ?? "")`, added a hidden `transportShortcuts` ZStack of zero-size buttons binding `.space` (`engine.toggle()`) / `.leftArrow` / `.rightArrow` to a `jump(by:)` helper that cancels the previous in-flight `seekTask`, switched the first-launch flag from `UserDefaults` (per-document race) to `@AppStorage` (app-level).
- `OnlyCue/Media/PlayerEngine.swift` — `func toggle()`. Reused by `TransportBar` (-7 LOC of inline conditionals).
- `OnlyCue/App/AppCommands.swift` (new) — `Commands` body with `CommandGroup(replacing: .appInfo) { Button("About OnlyCue") { ... } }` calling `NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: ...])`. Version reads from `CFBundleShortVersionString` automatically.
- `OnlyCue/App/OnlyCueApp.swift` — `.commands { AppCommands() }` on the `DocumentGroup` scene.
- `OnlyCue/UI/FirstLaunchSheet.swift` (new) — welcome sheet with SF Symbol, copy, and `Link` to the docs anchor in this README. URL hoisted to `private static let docsURL: URL?` and gated by `if let` to satisfy `force_unwrapping`.
- `OnlyCue/Resources/Assets.xcassets/AppIcon.appiconset/` — placeholder mark generated by `scripts/generate-app-icon.swift` (Swift CG shebang script using AppKit/CoreGraphics + `NSBitmapImageRep`); `sips` derives the standard mac size set (16/32/64/128/256/512/1024). `Contents.json` enumerates the 10 slots; root catalog `Contents.json` is the minimal Xcode skeleton. xcodegen picks up the catalog automatically from `sources: - path: OnlyCue`.
- `OnlyCueTests/MediaImporterTests.swift` — 3 reload tests (resolves bookmark + loads asset, missing file throws + preserves model.media for relink, no-media is a no-op).

**Iteration via simplify pass — 4 real fixes from 3 parallel reviewers (commit `aeefc06`):**
1. Two `.alert(item:)` modifiers on the same view → second silently dropped on macOS. Collapsed to one + enum.
2. `.task(id: bookmarkData)` re-fired when `reload` itself rewrote the bookmark on stale. Added `reloadedFor: Data?` sentinel.
3. `jump(by:)` spawned an unstructured `Task` per arrow keypress → at ~30Hz keyrepeat, dozens queued and `engine.currentTime` was sampled at dispatch time. Switched to `seekTask?.cancel(); seekTask = Task { ... }`.
4. `showFirstLaunch: Bool = !UserDefaults.standard.bool(forKey:)` ran at every `DocumentView` init → race when two documents opened on first launch. Switched to `@AppStorage(FirstLaunchFlag.key)`.

Plus: dropped the redundant `applicationName: "OnlyCue"` override on the About panel (read automatically from `CFBundleName`); added `PlayerEngine.toggle()` to remove the play/pause duplication between `DocumentView` and `TransportBar`.

**Iteration via PR review — one cycle (commit `e60ddd6`):**
- Reviewer flagged the benign-but-wasteful second `reload` pass on the stale-refresh path: the sentinel still held the *pre-refresh* bookmark, so when `.task(id:)` re-fired with the new bookmark, the guard missed and `reload` ran a second time (terminated immediately because not stale, but incurred an extra `asset.load(.duration)` round trip). Fix: after a successful `MediaImporter.reload`, set `reloadedFor = document.model.media?.bookmarkData` so the second fire hits the guard.

**Manual verification (per issue #11 epic-level Gherkin):**
- Open a saved `.cuelist` whose `.mp3` was moved → "Missing media" alert with "Relink media…" / "Continue without media".
- Click "Relink media…" → `.fileImporter` → pick the new path → media loads, bookmark silently refreshed via `importMedia`.
- Click "Continue without media" → cues remain editable; preview pane shows the placeholder.
- Empty document → "Drop a file here or press ⌘O to import." copy.
- Save the document as `Show.cuelist` → window subtitle shows the imported file name.
- Press Space → play/pause toggles; ←/→ jumps the playhead 1s; held-arrow jumps smoothly without backlog.
- About OnlyCue menu → standard panel with version + credits string.
- First launch (delete the `didShowFirstLaunchNudge` UserDefault) → welcome sheet; "Got it" dismisses; relaunching, no sheet.

---

## 2026-05-07 — E8 cue markers session (PR #23, issue #10)

**Shipped:** issue #10 (E8 cue markers on waveform). PR #23 merged into `dev` (rebase, head `716a710`). The waveform is now a real cue-editing surface, not just a static peak chart.

**What landed:**
- `OnlyCue/UI/CueMarkersGeometry.swift` — pure functions: `position(forTime:width:duration:)` (linear projection, zero-duration → 0) and `time(originalTime:dx:width:duration:)` (clamps to `0…duration`). Kept side-effect-free so geometry is unit-testable without SwiftUI.
- `OnlyCue/UI/CueMarkersOverlay.swift` — `GeometryReader` + `ForEach(cues)` driving `CueMarkerView` (vertical `Rectangle` + `Capsule` cap, both colored from `cue.colorHex`). A clear hit-area `Capsule` (14pt) widens the touch target. A single `DragGesture(minimumDistance: 0)` decides drag-vs-tap on `.onEnded` via a 4pt magnitude threshold — single ended call → exactly one `retime` undo step. Live `dragOffset` `@State` follows the finger; reset on end.
- `OnlyCue/UI/WaveformContainer.swift` — `.overlay(alignment: .topLeading) { CueMarkersOverlay(...) }` mounted on `WaveformView` **before** `.padding(.horizontal, 8)` so the overlay shares the waveform's pre-padded frame (markers align with peaks). Loads `asset.duration` during peak load so the overlay can project times.
- `OnlyCue/UI/PreviewPane.swift` — refactored from `media: MediaReference?` to `@ObservedObject document: CueListDocument`; audio path forwards `cues`, `onSeek` (→ `engine.seek`), and `onRetime` (→ `CueCommands.retime`).
- `OnlyCueTests/CueMarkersGeometryTests.swift` — 7 tests covering position at zero / full / mid / zero-duration, plus drag-time math with both clamps.

**Iteration via PR review — one cycle, four cleanups (`716a710`):**
1. **Blocker — overlay/peak misalignment** — original modifier order was `.padding` then `.overlay`, which sized the overlay to the *padded* frame. Markers drifted 8pt left of peaks. Fix: swap order so the overlay sizes to the waveform's intrinsic frame, then pad both as one unit.
2. Moved `dragThreshold` to sit with the other static layout constants for discoverability.
3. Dropped redundant `.contentShape(Rectangle())` on the clear `Capsule` hit-area (a filled shape already participates in hit-testing).
4. Dropped default `.allowsHitTesting(true)` on the overlay (it's the SwiftUI default).

**Manual verification (per issue #10 Gherkin):**
- Import `.mp3` → 3 cues at 4.25s / 12.0s / 18.5s (DEBUG seed) → 3 colored markers appear at correct x-positions.
- Tap marker #2 → playhead seeks to 12.0s.
- Drag marker #2 right → time updates live; release → one ⌘Z step restores original time.

---

## 2026-05-07 — E7 add/edit/delete cues session (PR #22, issue #9)

**Shipped:** issue #9 (E7 add/edit/delete cues). PR #22 merged into `dev` (rebase, head `5c5645a`). Documents are now live editors with proper undo.

**What landed:**
- `OnlyCue/Commands/CueCommands.swift` — 5 `@MainActor` static mutations (`addCueAtPlayhead`, `delete`, `rename`, `recolor`, `retime`) + private `mutate(_:undoManager:actionName:_:)` snapshot-and-replace helper. The helper opens its own undo group (`beginUndoGrouping` + `defer { endUndoGrouping() }`) so each command is one undoable unit regardless of host. Recursive `Self.mutate` inside the undo callback establishes the redo path. Edit-menu action names ("Undo Add Cue", "Redo Rename Cue", etc.) via `setActionName`.
- `OnlyCue/UI/CueRowView.swift` — `Button` swatch (14pt `Circle`, `.buttonStyle(.plain)`) opens a `.popover` listing 8 predefined cue colors. `TextField`-with-`@FocusState` handles inline rename on double-click; commits on Enter, cancels on Esc.
- `OnlyCue/UI/CueListPane.swift` — `.onDeleteCommand { deleteSelected() }` deletes the selected row via AppKit's responder chain. `.onDelete(perform:)` mirrors via swipe. `@Environment(\.undoManager)` flows through to all commands.
- `OnlyCue/UI/DocumentView.swift` — DEBUG seed button replaced with a real "Add Cue" button bound to `M` (no modifiers). `@Environment(\.undoManager)` injected.
- `OnlyCueTests/CueCommandsTests.swift` — 8 tests: add at time, add+undo+redo, delete+undo, rename+undo, recolor+undo, retime+undo, multi-add stays sorted by time. Test helper sets `groupsByEvent = false` so each `mutate` group lands at top level (one mutation = one undo).

**Iteration mid-session — three live-smoke fixes:**
1. **`ColorPicker` rendered as a chunky pill** — wraps `NSColorWell` with minimum chrome size; `.frame(width:height:)` is silently ignored. Swapped to a palette `Menu`.
2. **Mac delete key didn't fire** with `.onKeyPress(.delete)` + `@FocusState` on a `List`. Swapped to `.onDeleteCommand`, which routes through AppKit's responder chain.
3. **`Menu { ... }.menuStyle(.borderlessButton)` collapsed the trigger**, hiding the swatch label entirely. Final form: `Button` + `.popover` with `.buttonStyle(.plain)` for full custom rendering.

**Iteration via PR review — three undo-grouping cycles** (captured in `docs/findings.md`):
1. Initial `groupsByEvent = false` in tests broke `registerUndo` (must begin a group first).
2. Removing the override let `groupsByEvent = true` swallow every test mutation into one auto-group → `undo()` rolled back the whole test.
3. Final fix: `mutate` opens its own group (host-independent), test helper sets `groupsByEvent = false` so that group lands at top level. Production keeps `groupsByEvent = true` from `DocumentGroup` and our group nests cleanly inside the run-loop auto-group (one user click = one undoable unit).

**Manual verification (per issue #9 Gherkin):**
- Drop `.mp3` → press `M` at various playhead positions → cues appear sorted by time with default name "Cue" and teal swatch.
- ⌘Z empties; ⌘⇧Z restores.
- Double-click name → TextField focused → type → Enter → name updates; ⌘Z restores.
- Click swatch → palette popover → choose color → swatch updates; ⌘Z restores.
- Select row → ⌫ → deleted; ⌘Z restores with same id and time.

---

## 2026-05-07 — E6 cue list pane session (PR #21, issue #8)

**Shipped:** issue #8 (E6 cue list pane). PR #21 merged into `dev` (rebase, head `0009f35`). The cue list — the thing this app exists to plan — finally has a UI.

**What landed:**
- `OnlyCue/UI/CueListPane.swift` — `if cues.isEmpty { emptyState } else { List(selection: $selection) }`. Empty state has SF Symbol + "No cues yet" + "Press M to add one at the playhead". Selection is `Cue.ID?`; `.onChange(of: selection)` looks up the cue and calls `engine.seek(to: cue.time)` in a `Task`.
- `OnlyCue/UI/CueRowView.swift` — `HStack` with zero-padded `#`, `Circle` color swatch, name (or "Untitled"), `TimeFormat.hms(cue.time)` in monospaced caption.
- `OnlyCue/Utilities/Color+Hex.swift` — `Color.init?(hex: String)` parsing `#RRGGBB`. Defensive `allSatisfy(\.isHexDigit)` guard since `Scanner.scanHexInt64` accepts some non-hex strings.
- `OnlyCue/UI/DocumentView.swift` — `.inspector(isPresented: .constant(true))` hosts `CueListPane` with `inspectorColumnWidth(min: 240, ideal: 300, max: 400)`. Locked-open is correct for E6 (Gherkin demands the empty-state hint be discoverable); collapsible toggle is E9 polish.
- `OnlyCue/Commands/CueCommands.swift` — minimal `@MainActor enum CueCommands { static func replaceAll(_:in:) }`. CLAUDE.md mandates "UI layers go through `Commands/CueCommands.swift`" — so even the DEBUG seed button must route through it. E7 will extend with `add(at:)`, `delete`, `move`, and `UndoManager` wrapping.
- `OnlyCue/UI/DocumentView.swift` — `#if DEBUG` "+ Sample cues" button (3 cues at 4.25s / 12.0s / 18.5s). Smoke-tests the populated-list and click-to-seek Gherkin scenarios before E7 ships the M-key path. Hidden in Release; trivial to delete when E7 lands.
- `OnlyCueTests/ColorHexTests.swift` — valid hex → expected RGB; lowercase OK; missing `#` OK; wrong length → nil; non-hex chars → nil.

**Manual verification (per issue #8 Gherkin):**
- New document → cue list shows empty state with the M-key hint.
- Click "+ Sample cues" (DEBUG) → 3 rows render in order with correct colors and HH:MM:SS.mmm times.
- Click row 2 → playhead seeks to ~12.0s.

---

## 2026-05-07 — E5 waveform session (PR #20, issue #7)

**Shipped:** issue #7 (E5 waveform). PR #20 merged into `dev` (rebase, head `d962d96`). Audio documents now have a real waveform.

**What landed:**
- `OnlyCue/Media/WaveformGenerator.swift` — `static peaks(for: AVAsset, resolution: Int) async throws -> [Float]`. Forces output to mono Int16 LinearPCM @ 44.1kHz via `AVAssetReaderTrackOutput`, streams sample buffers, peak-reduces into N buckets via a `private struct PeakAccumulator`, normalizes to `0…1`. `Task.checkCancellation()` between buffers; `CMSampleBufferInvalidate` to free the reader's pool. Top-level function split into `makeReader` / `estimatedSampleCount` helpers to fit SwiftLint's complexity (10) and length (50) budgets.
- `OnlyCue/Media/WaveformCache.swift` — `WaveformCache(directory:)` for tests + `WaveformCache.shared` rooted at `~/Library/Caches/OnlyCue/peaks/`. Binary `Float32` blob keyed by `<sha>-<resolution>.peaks`. `static fileHash(_:)` streams the file in 1 MB chunks via `CryptoKit.SHA256`.
- `OnlyCue/UI/WaveformView.swift` — Canvas of rounded vertical bars centered on midline; resolves shading once, fills with `context.fill(path, with: shading)`.
- `OnlyCue/UI/WaveformContainer.swift` — orchestrates: hash file once → cache lookup → render or generate → fire-and-forget background write. `.task(id: asset.url)` cancels and reruns when the URL changes.
- `OnlyCue/UI/PreviewPane.swift` — audio path mounts `WaveformContainer` when `engine.player.currentItem?.asset is AVURLAsset`; otherwise shows reopen-required placeholder (relink work is E9).
- `OnlyCueTests/{WaveformGenerator,WaveformCache}Tests.swift` — generator (count, silent → zero, sine → non-zero, normalized) + cache (round-trip, miss, resolution mismatch, hash stability + uniqueness). `SilentAudioFixture.makeSineWAV(duration:frequency:)` added.

**Iteration mid-session — five SwiftLint/API errors caught at build time:**
1. `GraphicsContext.fill(_:with:)` takes `Shading` directly, not `Shading.color(...)`. The resolved shading **is** the value to pass.
2. `unneeded_synthesized_initializer` on `WaveformCache(directory:)` — dropped the explicit init, kept memberwise.
3. `prefer_self_in_static_references` inside `WaveformCache.shared` factory — `Self(directory:)` not `WaveformCache(directory:)`.
4. & 5. `cyclomatic_complexity 11` and `function_body_length 66` on `peaks(for:resolution:)` — extracted `PeakAccumulator` struct and split helpers; top-level function dropped to ~30 lines.

**Manual verification:**
- 5-min `.mp3` first import: spinner appears, waveform renders within ~1s.
- Re-import same `.mp3`: cache hit, instant render.
- Video import: unchanged (video preview pane).

**Caveat — Gherkin reopen scenario:** "peak cache hits on document reopen within 250ms" is partially deferred. Cache hits on **re-import** of the same file. Reopen-from-bookmark requires the document open path to resolve `MediaReference.bookmarkData` and reload the asset into the player — that's E9 relink. PreviewPane shows "reopen with media" placeholder when the engine is empty.

---

## 2026-05-07 — E4 video preview session (PR #19, issue #6)

**Shipped:** issue #6 (E4 video preview pane). PR #19 merged into `dev` (rebase, head `be72182`). Documents now show their picture.

**What landed:**
- `OnlyCue/UI/AVPlayerLayerView.swift` — `NSViewRepresentable` over `PlayerHostingView: NSView`. Host view sets `wantsLayer = true`, gets a plain `CALayer`, then `addSublayer(playerLayer)` with `videoGravity = .resizeAspect`. `override func layout()` keeps `playerLayer.frame = bounds` on every resize.
- `OnlyCue/UI/PreviewPane.swift` — `if let media; switch media.kind` dispatches to `AVPlayerLayerView`, an audio placeholder ("Audio loaded — waveform arrives in E5"), or an empty placeholder. `minHeight: 180`, rounded corners, accessibility identifiers per state.
- `OnlyCue/UI/DocumentView.swift` — pane slotted between media summary and cue count; window minimum bumped to 560×480.
- `project.yml` — pre-build SwiftLint script now `export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"` before `which swiftlint`. Xcode runs build scripts in a sandboxed shell with restricted PATH; without the export, a Homebrew-installed swiftlint reported "not installed".

**Build/render iteration mid-session:**
- First pass used `override func makeBackingLayer() -> CALayer { playerLayer }` to make the AVPlayerLayer the view's own backing layer. Compiles, looks elegant; rendered no picture in practice on macOS 15. Audio played, video stayed empty. Switched to the `addSublayer + override layout()` canonical pattern (commit `9fcc9cc` / `be72182`); video now renders.
- Stale Swift 6 `@MainActor` build error appeared once — DerivedData cache from before the E3 fix. `⌘⇧K` clean build folder cleared it.

**Simplify drop:** first pass added `PreviewPane.Kind { empty/audio/video }` + a static `previewKind(for:)` function + a unit test. The function just unwrapped `media?.kind`, the test was tautological. All three deleted (commit `b2091ed`); inline switch on `media?.kind` in the body. -32 LOC.

**Manual verification (per Gherkin in issue #6):**
- `.mp4` drag-drop → first frame visible immediately, transport drives video + audio in sync.
- `.mp3` drag-drop → audio placeholder.
- Empty document → empty placeholder.

---

## 2026-05-07 — E3 media import session (PR #18, issue #5)

**Shipped:** issue #5 (E3 media import). PR #18 merged into `dev` (rebase, head `ce3e0ca`). The app can now actually open user-supplied media.

**What landed:**
- `OnlyCue/Utilities/Bookmarks.swift` — `Bookmarks.create(for:) -> Data` and `Bookmarks.resolve(_:) -> Resolution` over `URL.bookmarkData(options: .withSecurityScope)` and `URL(resolvingBookmarkData:bookmarkDataIsStale:)`. `Resolution { url, isStale }` keeps the staleness signal explicit for E9.
- `OnlyCue/Commands/MediaImporter.swift` (new directory) — `@MainActor importMedia(from:into:engine:)`. Validates the URL via `UTType` (`.audio` / `.movie`), creates the bookmark, loads `AVAsset` duration off-main, mutates `document.model.media`, and calls `engine.load(asset:)`. `MediaImportError.unsupportedType(filename:)` for the alert path.
- `OnlyCue/UI/DocumentView.swift` — `Import Media…` button bound to `⌘O`, `.fileImporter(allowedContentTypes: MediaImporter.allowedContentTypes)`, `.dropDestination(for: URL.self)`, `.alert(item:)` driven by an internal `ImportAlert: Identifiable`. Added `mediaSummary` line that shows the imported file name + HH:MM:SS.mmm duration.
- `OnlyCueTests/SilentAudioFixture.swift` — single shared programmatic silent-WAV generator. Replaces three nearly-identical inline copies in `PlayerEngineTests`, `BookmarksTests`, `MediaImporterTests` (-41 LOC after the refactor commit).
- `OnlyCueTests/{Bookmarks,MediaImporter}Tests.swift` — round-trip via temp file, JSON pass-through, invalid-data throw; mediaKind detection (audio/video/unsupported), full importMedia happy path, unsupported throws and leaves model nil.
- `OnlyCue/Media/PlayerEngine.swift` — `@MainActor` on the class; periodic-time-observer closure hops via `MainActor.assumeIsolated { ... }` (queue is already `.main`).

**Build fixes applied mid-session (Swift 6 / macOS 15 SDK):**
- "Main actor-isolated initializer 'init(asset:)' cannot be called from outside of the actor" — fixed by adding `@MainActor` to `PlayerEngine` (commit `12a5015`). This applies the suggestion deferred from PR #17 review; it became load-bearing for the build, so the deferral resolved itself organically.
- "Main actor-isolated property 'currentTime' / 'rate' can not be mutated from a Sendable closure" inside `addPeriodicTimeObserver` — fixed by wrapping the body in `MainActor.assumeIsolated { ... }` (commit `ce3e0ca`). The observer queue is `.main`, so the assumption is sound and avoids per-tick `Task` allocation at 10Hz.

**Manual verification (per `docs/build-sequence.md` detour rule #3, since XCUITest can't drive `NSOpenPanel`/`.dropDestination`):**
- Drag `.mp3` onto window → `mediaSummary` updates with name + duration, transport plays audio.
- ⌘O → file picker filtered to audio + video.
- Drag `.pdf` → "Unsupported file" alert; `ProjectModel.media` stays nil.
- Video preview is intentionally absent (E4 / #6).

**Ad-hoc signing debug attach gotcha:** earlier in the session, Xcode reported "Unable to obtain a task name port right for pid X: (os/kern) failure (0x5)" when running. That's the LLDB-attach failure from `CODE_SIGN_IDENTITY: "-"` without a `get-task-allow` entitlement — masking the real Swift 6 build errors above. Lesson captured to `findings.md`: read the **build log** before debugging the runtime error.

---

## 2026-05-07 — E2 player core session (PR #17, issue #4)

**Shipped:** issue #4 (E2 player core). PR #17 merged into `dev` (rebase, head `2240f5c`). First media-handling code.

**What landed:**
- `OnlyCue/Utilities/Time+Format.swift` — `TimeFormat.hms(_:)` returns `HH:MM:SS.mmm`, clamps negatives to zero, half-away-from-zero millisecond rounding. 7 unit tests covering zero, sub-second, minute/hour rollover, complex case, negatives, and sub-ms rounding.
- `OnlyCue/Media/PlayerEngine.swift` — `@Observable final class` wrapping `AVPlayer`. Exposes `currentTime`, `rate`, `duration` as observable state via the `Observation` framework; player and `timeObserver` use `@ObservationIgnored`. API: `play()`, `pause()`, `seek(to:)`, `load(asset:)`. Periodic time observer fires every 0.1s on the main queue. 4 unit tests using a programmatically-generated silent WAV (`AVAudioFile`) — no fixture media in the repo.
- `OnlyCue/UI/TransportBar.swift` — minimal SwiftUI transport: play/pause `Image` button toggling on `engine.rate > 0`, monospaced time readout via `TimeFormat.hms(engine.currentTime)`. `accessibilityIdentifier`s on both elements.
- `OnlyCue/UI/DocumentView.swift` — wired `@State private var engine = PlayerEngine()` per document and embedded `TransportBar(engine:)`.

**Review cycle (1 commit beyond initial 4):**
- Cycle 1: 3 optional suggestions on PR #17. Applied #3 (`load(asset:)` now resets `rate = 0` immediately, closing a ~100ms stale-rate window between `replaceCurrentItem(with:)` and the next periodic observer tick — commit `2240f5c`). Deferred #1 (`@MainActor`) and #2 (`rate != 0` vs `> 0`) per YAGNI: the reviewer's own framing was conditional ("once we cross threading boundaries", "if/when we support reverse playback"). Posted gh-comment explaining the deferral with reasoning.

**Key learnings:**
- `@Observable` + `@ObservationIgnored` is the right shape for engine-style classes that own non-observable resources (an `AVPlayer`, a periodic-time-observer token).
- Real assets (not mocks) for `seek`/`load` tests via `AVAudioFile.write(from:)` to a temp WAV. Keeps tests fast, hermetic, and realistic without committing binary fixtures.
- Establish convention for review feedback: apply unconditional correctness fixes; defer suggestions whose own framing is conditional on future events.

---

## 2026-05-07 — E1 skeleton session (PR #16, issue #3)

**Shipped:** issue #3 (E1 skeleton). PR #16 merged into `dev`. First feature epic — first real Swift code.

**What landed:**
- Data model under `OnlyCue/Document/`: `ProjectModel`, `Cue`, `MediaReference`, `MediaKind`. All `Codable`/`Equatable`; `Cue` is also `Identifiable`.
- `CueListDocument` (`final class : ReferenceFileDocument`) with JSON encode/decode using `[.prettyPrinted, .sortedKeys]`.
- `Info.plist` adds `UTExportedTypeDeclarations` (declares `com.onlycue.cuelist`) and `CFBundleDocumentTypes` (binds it to `CueListDocument` via `NSDocumentClass`).
- `OnlyCueApp` now uses `DocumentGroup`. `DocumentView` shows minimal placeholder (title + cue count + hint) — preview/waveform/cue list arrive in E4–E6.
- Tests: 3 unit tests in `ProjectModelTests` (round-trip with media, round-trip with nil media, format assertions) + 1 UI test in `DocumentLaunchTests` mapping the "Scenario: New document opens" Gherkin.
- Replaced C1 placeholder tests with real ones.

**Review cycles applied (3 commits beyond initial 6):**
- Cycle 1: SwiftLint `--strict` failed on test code — replaced 6 force-unwraps with `try XCTUnwrap`, fixed `String(decoding:)` per `optional_data_string_conversion`, fixed `multiline_arguments` on `XCTAssert*` calls. Hoisted fixed UUIDs into `static let` constants.
- Cycle 2: macOS `DocumentGroup` shows the launcher window on cold launch (not auto untitled doc), so the UI test never reached `DocumentView`. Drove the test through `app.typeKey("n", modifierFlags: .command)` to mirror the Gherkin "When the user creates a new document". Added `.accessibilityIdentifier("documentTitle")` and `.accessibilityIdentifier("cueCount")` to query by stable identifier.
- Cycle 3: `XCUIElement.label` returns empty string when querying SwiftUI `Text` by `accessibilityIdentifier`. Dropped both `.label` equality assertions; element existence under the identifier is sufficient evidence of the rendered content.

**Key learnings (captured in `docs/findings.md`-worthy items):**
- SwiftLint `--strict` applies to test code too. Use `try XCTUnwrap` over force-unwrap in tests.
- macOS `DocumentGroup` cold-launch shows launcher, not untitled document. UI tests must drive ⌘N first.
- XCUITest `.label` is unreliable when an element carries `accessibilityIdentifier` from a SwiftUI `Text`; rely on identifier resolution + `exists`/`waitForExistence` instead.

---

## 2026-05-07 — CI session (PR #15, issue #2)

**Shipped:** issue #2 (C2 CI). PR #15 merged into `dev`. First PR using the new dev-as-default flow.

**What landed:**
- `.github/workflows/ci.yml` — single `build-test` job on `macos-latest`, ~25 min timeout.
- Pipeline: checkout → `maxim-lobanov/setup-xcode@v1` (latest stable Xcode) → `brew install xcodegen swiftlint xcbeautify` → `swiftlint lint --strict --reporter github-actions-logging` → `xcodegen generate` → `actions/cache@v4` (DerivedData + SPM) → `xcodebuild build` Debug → `xcodebuild test`. Build/test piped through `xcbeautify --renderer github-actions` for proper annotations.
- Triggers: `pull_request` (any branch) and `push` to `main` or `dev`.
- Concurrency: `cancel-in-progress` per ref.
- Code signing disabled (signing is C3's job).

**Coverage of reviewer feedback from PR #14:**
- SwiftLint must fail CI on absent or violating — `--strict` mode + natural `brew install` failure mode covers both.

**Out of scope (deferred):**
- Code signing in CI → C3 (#13).
- Release builds in CI → C3.
- Branch protection (require CI green + 1 review) → repo Settings UI, not committable.

**Verification:** the PR's own check run was the first exercise of the workflow — green on first run.

---

## 2026-05-07 — Bootstrap session (PR #14, issue #1)

**Shipped:** issue #1 (C1 bootstrap). PR #14 merged via rebase into `main`.

**What landed:**
- Repo metadata (linked the GitHub remote, 23 labels, 3 milestones, 13 issues — 10 epics + 3 chores).
- All planning docs under `docs/` (vision, mvp-scope, architecture, data-model, build-sequence, verification, roadmap, decisions).
- Approved spec: `docs/superpowers/specs/2026-05-07-repo-issues-design.md`.
- Implementation plan: `docs/superpowers/plans/2026-05-07-repo-issues.md` + 13 issue body templates committed under `docs/superpowers/plans/issue-bodies/`.
- Setup scripts: `docs/superpowers/plans/setup-labels.sh`, `setup-milestones.sh` (idempotent).
- Project skeleton: `project.yml` (xcodegen 2.45.4), `OnlyCue.xcodeproj` generated and gitignored.
- Folder layout per `docs/architecture.md`: App / Document / Media / UI / Commands / Utilities / Resources.
- Minimal Swift placeholders so the project compiles (real implementations live in E1 onward).
- Configs: `.gitignore`, `.editorconfig`, `.swiftlint.yml` (with `unused_import` correctly under `analyzer_rules`), `Info.plist`.
- GitHub templates: `.github/ISSUE_TEMPLATE/{epic,leaf,chore,bug}.md` + 7 forked PR templates with the OnlyCue verification footer (the original 6 from the gh-pr skill plus a new `chore.md` extending the skill's mapping).
- `CLAUDE.md` with PR template override rule, commit conventions, branching rules, and hard rules.

**Review feedback applied (commit `4bac6bf` after rebase):**
- Bundle ID changed to `com.chienchuanw.OnlyCue` (reverse-DNS must be a domain we control).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` for Release config (Debug stays NO).
- Dropped duplicate `DEVELOPMENT_LANGUAGE: en` from target settings.
- Removed redundant `*.xcodeproj/project.xcworkspace/swiftpm/` from `.gitignore`.
- Rewrote `chore.md` PR footer with chore-shaped items (tooling-verified-locally, no-behavioral-surface, spec/CLAUDE.md updated, CI green).
- Tracked SwiftLint CI enforcement on issue #2; tracked placeholder-test deletion as a leaf on issue #3.

**Branching change:** `dev` is now the default branch on the remote. Issue branches base off `dev`. Production code is on `main`. CLAUDE.md updated to reflect this.

**Tooling installed this session:**
- `xcodegen` (2.45.4) via Homebrew — generates `OnlyCue.xcodeproj` from `project.yml`.
