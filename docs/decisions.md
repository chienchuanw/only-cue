# Architecture Decision Records

Append-only log of locked decisions. Newer entries on top. Each ADR captures **what**, **why**, and **what it costs to reverse**.

ADR template:

```markdown
## ADR-NNN — Title
**Date**: YYYY-MM-DD
**Status**: Accepted | Superseded by ADR-MMM
**Decision**: One sentence.
**Why**: 2–4 sentences.
**Reversal cost**: How painful would changing this be?
```

---

## ADR-014 — grandMA3 / grandMA2 export targets are best-effort CSV variants with renamed headers
**Date**: 2026-05-10
**Status**: Accepted
**Decision**: `ExportTarget.ma3` and `ExportTarget.ma2` produce CSV with the same row shape as the generic CSV target but with grandMA-conventional column labels: `Cue,Name,Trig Time,Fade In,Fade Out,Type,Note`. Both share a single `CueCSVExporter.maCSV` formatter (MA3 and MA2 are identical at the format layer; the case distinction exists so the picker can label them separately and the file extension / content type stay consistent). The picker UI labels both options with "(best-effort)" so users know to validate against their console before relying on the format in production.
**Why**: Epic #34 calls for grandMA3 and grandMA2 importer formats so users handing off shows to grandMA consoles can skip the spreadsheet-bridge step. We don't have authoritative format documentation in the repo, and shipping a wrong format silently is worse than not shipping. The renamed-header best-effort variant gives users a usable starting point; the "(best-effort)" picker label and ADR caveat surface the validation expectation. Consolidating MA3 + MA2 to a single formatter avoids duplicating the same code twice when no concrete divergence is known yet — the case distinction stays at the enum level so a future split is a single switch-branch change. The column convention is documented explicitly here so it can be amended once a real-world MA user reports specifics.
**Reversal cost**: Low. Each target's format function is a single switch branch; renaming columns or splitting MA3 from MA2 are mechanical refactors. Removing the targets entirely is a single-row enum delete + a small picker re-render. No persistence consequences.

## ADR-013 — Export pipeline is two orthogonal pure functions plus an AppKit-side action
**Date**: 2026-05-10
**Status**: Accepted
**Decision**: Console export (#34) is built as three discrete modules: a `CueExportFilter` (pure `(cues, onlyTypeIDs) -> [Cue]`), a `CueCSVExporter` with `csv(...)` and `tsv(...)` methods both delegating to a private `format(cues:typeNamesByID:delimiter:)` helper that threads the active delimiter into a single escape predicate, and a `CueCSVExportAction` that wraps the pure pair with `NSSavePanel` + disk write. The File menu posts `.exportCuesToCSVRequested`; `DocumentView` receives it and calls the action. Empty filter set is "no filter" passthrough.
**Why**: The epic-#34 Gherkin scenario ("Then a file ... contains only Lighting cues") requires a filter that operates between the cue list and any output format, so the filter has to be format-agnostic. Future grandMA2/3 formats add new exporter modules with the same `(cues, typeNamesByID) -> String` signature and compose with the existing filter without modification. The format-aware escape predicate (single helper, parameterized delimiter) gives CSV and TSV correct, asymmetric escape behavior (commas pass through unescaped in TSV; tabs pass through in CSV) without code duplication. Keeping AppKit (`NSSavePanel`) in a separate action file keeps `DocumentView`'s SwiftUI body free of imperative IO and stays under SwiftLint's `type_body_length` cap. The notification-bridge wiring matches the existing `.importMediaRequested` precedent so a future toolbar button or AppleScript hook adds a poster, not exporter code.
**Reversal cost**: Low. Each module is independent; collapsing them back into a single function (or splitting the exporter further per-format) is a mechanical refactor with no schema or persistence consequences. The notification name is a string constant; adding/removing entry points is local.

## ADR-012 — Color resolves from `CuePointType`; drop transitional `Cue.colorHex` (schema v6)
**Date**: 2026-05-08
**Status**: Accepted
**Decision**: Remove `Cue.colorHex` from the model. Every UI site that paints a cue color (the row swatch, the waveform marker overlay) resolves color from the cue's `CuePointType` via a new `ProjectModel.colorHex(for cue: Cue) -> String?` helper. The per-row palette popover and `CueCommands.recolor` are deleted; users change a cue's color by picking a different Type from the inspector picker. Bump `schemaVersion` 5 → 6 with a deterministic `migrateFromV5` that decodes the v5 envelope and constructs v6 cues without the field. v1, v2, v3, v4 chains keep their legacy `colorHex` decode for backward-compat parsing but their `toCue()` methods drop it; every pre-v6 source lands on a v6 model.
**Why**: PR #53 (cue inspector) made the staleness of per-cue color visible: changing Type via the inspector picker only mutates `cue.typeID`, leaving `cue.colorHex` on the previous Type's color. Color is a Type-derived fact, not per-cue state, so the field was redundant from PR #45 (when CuePointType landed) and now actively harmful as a UI/model disagreement source. The transitional duplication kept the MVP's color-picker UX working through #45/#47/#51/#53; the inspector now provides the single editing surface for Type membership and the popover's per-cue palette is deprecated. Snapshotting the Type's color into `cue.colorHex` at `setType` time was considered but rejected: it would convert the disagreement into stale-cache drift (recoloring a Type wouldn't update existing cues) and add two failure modes without removing the underlying issue. UX trade-off accepted: until a Type management UI ships, users only have whatever Types exist (default project has one, "General"), so per-cue color choice is temporarily reduced to "pick from existing Types".
**Reversal cost**: Medium. The migration is one-way (pre-v6 readers cannot open v6 files). Reverting would require a v6 → v5 down-migration that synthesizes per-cue `colorHex` from the Type at decode — losslessly recoverable, but the popover and `recolor` would need to come back to give users editing power again.

## ADR-011 — `Cue.fadeTime` as a struct with synthesized Codable; symmetric vs split is derived (schema v5)
**Date**: 2026-05-08
**Status**: Accepted
**Decision**: Add `Cue.fadeTime: FadeTime` as a required field. `FadeTime` is a value struct with two `TimeInterval` fields, `fadeIn` and `fadeOut`, and synthesized Codable. Symmetric vs split is a derived fact (`fadeIn == fadeOut`), implemented by a pure string parser (`"1"`/`"1.5"` → symmetric, `"1/2"` → split) and a canonical formatter that drops trailing `.0` on whole numbers. Bump `schemaVersion` 4 → 5 with a `migrateFromV4` that backfills `.symmetric(0)` (no fade) on every existing cue; v1, v2, and v3 chains backfill at the `LegacyCue.toCue` / `LegacyV3Cue.toCue` boundary so any pre-v5 source lands on a v5 model with valid fade data.
**Why**: Console exports (#34) need a fade-time column per cue, with split-fade syntax supported. Modelling fade as a `struct { fadeIn, fadeOut }` with synthesized Codable keeps the JSON shape stable and compile-checked, avoids a custom encoder, and makes future cue-inspector UI binding trivial (two `var` fields, two TextFields, no case rebuilding on every keystroke). An enum (`.symmetric(t)` / `.split(in:out:)`) was considered: it would encode the symmetric/split distinction at the type level rather than as a runtime equality check, but the duplication that adds (the parser already enforces parsing rules; the formatter already handles canonical output) is not worth the schema-evolution cost of custom Codable. The parser is the single gate for input validation — negative durations and malformed strings are rejected at parse time, not the struct boundary, mirroring the same trust-the-seam design we used for `Cue.cueNumber`.
**Reversal cost**: Medium. The migration is one-way (pre-v5 readers cannot open v5 files). Reverting would require a v5 → v4 down-migration that drops `fadeTime` — losing user fade data, but everything else survives.

## ADR-010 — `Cue.cueNumber` as a required model field with sort-order migration (schema v4)
**Date**: 2026-05-08
**Status**: Accepted
**Decision**: Add `Cue.cueNumber: Double` as a required user-facing cue number distinct from `Cue.id: UUID`. `addCueAtPlayhead` assigns the number by an "insert without ripple" rule: empty list → 1.0; at-end → predecessor's number + 1; between two cues → mid-point; before all → successor's number − 1 (may go negative on repeated inserts before the minimum). Bump `schemaVersion` 3 → 4 with a v3 → v4 migration that assigns sequential `cueNumber`s by time order within each item; v1 and v2 migrations chain through the same `assignCueNumbersBySort` helper so any pre-v4 source lands with valid numbers. The migration sort tie-breaks equal `time`s on `id.uuidString` lexicographic order (Swift's `Array.sorted(by:)` is not spec-guaranteed stable, so without this rule the `cueNumber` for cues sharing a timestamp would be implementation-defined; with it, re-running the migration on the same JSON always produces the identical assignment).
**Why**: Console exports (#34) need a cue number column that lighting designers actually edit. Modelling it as a required `Double` rather than `Optional<Double>` keeps every consumer (export, inspector, breakdown view) free of `Optional` plumbing — at the cost of a schema bump. We chose mid-point insertion over re-numbering on every insert so existing cue numbers are stable: a console operator who wrote down "GO 4" doesn't see it become "GO 5" because someone added a cue earlier in the timeline. Below-minimum inserts going negative is allowed and ugly; the cue inspector leaf will provide a "renumber from 1" command to clean up. Alternative algorithms (mid-point with virtual 0 floor; hard floor at 0.5) all collide on repeated insertion before the minimum, while negatives degrade gracefully.
**Reversal cost**: Medium. The migration is one-way (pre-v4 readers cannot open v4 files). Reverting would require a v4 → v3 down-migration that drops `cueNumber` — losing user numbering, but everything else survives.

## ADR-009 — CuePoint Types as first-class entities (schema v3)
**Date**: 2026-05-08
**Status**: Accepted
**Decision**: Introduce `CuePointType` as a first-class entity in `ProjectModel`. Every `Cue` references a Type by `typeID`. Bump `schemaVersion` to 3 with a v2 → v3 migration that seeds a default Type "General" (`#4ECDC4`) and assigns it to every existing cue. v1 → current chains through the same default-Type seeding.
**Why**: CuePoints organises shows by Type — lighting, sound, video, blocking, choreography — and this is what consoles consume on import. A flat per-cue color cannot express shared properties (default fade, hotkey 0–9, visibility, export-include) that belong to a category. Modelling Types as their own entity is the foundation for console export (#34), the breakdown view (#37), templates (#39), and number-key cue creation (later leaf of #32). Routing all of those through a single `cuePointTypes` array means no per-feature schema bumps later.
**Reversal cost**: Medium. The migration is one-way (v0.1.0 / multi-items v2 cannot open v3 files). Reverting would require a v3 → v2 down-migration that discards `cuePointTypes` and per-cue `typeID` — losing user organisation, but `colorHex` still survives on the cue.

## ADR-008 — Multi-media items live in one `.cuelist` (vs N documents)
**Date**: 2026-05-08
**Status**: Accepted
**Decision**: A single `.cuelist` document holds an array of `MediaItem`s, each with its own media reference and its own cue list. Multi-file imports append items in selection order. The previous one-media-per-document model is migrated forward via schema v2.
**Why**: A show is one project, not N. Forcing one window per media file leaves no place for show-level state (item order, active selection) and prevents users from drag-reordering across files. A workspace-of-files alternative was considered and rejected because it doubles the file count on disk and complicates sharing/version control. The schema bump is one-way (v0.1.0 readers cannot open v2), accepted because v0.1.0 is recent and the migration is deterministic.
**Reversal cost**: Medium. Reverting to single-media documents would require splitting existing v2 documents on save and adding either workspace files or external item ordering — both larger than the original change.

## ADR-007 — Sandbox off for MVP, ship via Developer ID DMG
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Distribute as a Developer ID-signed, notarized DMG. App Sandbox is **off**.
**Why**: The target audience is pro users who expect full filesystem access, virtual audio drivers, and console integrations. App Store sandbox would block features we want in phase 2 (LTC routing, OSC). DMG is the standard distribution form for tools in this space.
**Reversal cost**: Medium. Adopting sandbox later requires auditing every file/network access and adding entitlements. No code rewrite, but a careful audit.

## ADR-006 — JSON `.cuelist` document with referenced media
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Project files are pretty-printed JSON. Media is referenced via security-scoped bookmarks, not embedded.
**Why**: JSON diffs cleanly, is inspectable, and trivial to migrate. Embedding media would bloat files and complicate templates. Bookmarks survive moves within a volume and get a clean error path when they don't.
**Reversal cost**: Low for JSON-internal changes (versioned migrations). Medium if we ever want a self-contained bundle — we'd add a `.cuelistx` package format alongside, not replace the JSON.

## ADR-005 — Both audio and video supported from day 1
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: MVP supports `.mp3 .wav .aac .m4a .aiff` and `.mp4 .mov`.
**Why**: `AVPlayer` handles both behind one API. The marginal cost of adding video is one `NSViewRepresentable` wrapping `AVPlayerLayer`. Punting video would force the audience to wait for v2 just to plan TV broadcasts, which is half their work.
**Reversal cost**: N/A — adding more types later is trivial.

## ADR-004 — Lighting designers as the primary audience for v1
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Optimize the v1 workflow for lighting designers and show programmers, mirroring CuePoints.
**Why**: The reference product validates the workflow for this audience. A focused first release is easier to evaluate and easier to market. Broader audiences (podcasters, theater stage managers) can be reached later by extending — not redesigning.
**Reversal cost**: Low if we keep the cue model generic (we do). High if we hard-code lighting-specific UI strings or workflows; we won't.

## ADR-003 — MVP is a thin slice; LTC and exports defer to phase 2
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: v1 ships the core loop only: import → mark → save → reopen.
**Why**: LTC, templates, exports, and shortcut customization are valuable but uncorrelated risks. Shipping the core loop first proves the document model, the player, and the cue UX before we layer protocols on top.
**Reversal cost**: Low — phase 2 features are designed as additive seams.

## ADR-002 — MVVM with `@Observable` view models, document-based app
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: One `CueListDocument` per file via `DocumentGroup` + `ReferenceFileDocument`. View models use Swift's `@Observable` macro. UI never mutates the model directly — all mutations go through `CueCommands`.
**Why**: `DocumentGroup` gives us new/open/save/recents/autosave for free. Routing mutations through commands gives us undo correctness in one place and a future seam for collaboration, telemetry, and AI-suggested cues.
**Reversal cost**: High once views are written. Worth getting right early.

## ADR-001 — Native Swift + SwiftUI + AVFoundation; macOS 14+
**Date**: 2026-05-07
**Status**: Accepted
**Decision**: Build natively in Swift with SwiftUI for UI and AVFoundation for media. Minimum target is macOS 14 (Sonoma).
**Why**: Media performance and timecode-grade timing are the core of the product, and AVFoundation gives us frame-accurate seeking, hardware-accelerated decode, and a battle-tested player. Cross-platform stacks (Electron, Tauri, Flutter) all add a media-handling layer we'd have to maintain. Targeting macOS 14 unlocks `@Observable`, `inspector`, and modern `ScrollView` APIs we'll lean on.
**Reversal cost**: Total. Switching stacks means rewriting the app. We accept this lock-in.
