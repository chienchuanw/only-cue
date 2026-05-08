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

## ADR-011 — `Cue.fadeTime` as a struct with synthesized Codable; symmetric vs split is derived (schema v5)
**Date**: 2026-05-08
**Status**: Accepted
**Decision**: Add `Cue.fadeTime: FadeTime` as a required field. `FadeTime` is a value struct with two `TimeInterval` fields, `fadeIn` and `fadeOut`, and synthesized Codable. Symmetric vs split is a derived fact (`fadeIn == fadeOut`), implemented by a pure string parser (`"1"`/`"1.5"` → symmetric, `"1/2"` → split) and a canonical formatter that drops trailing `.0` on whole numbers. Bump `schemaVersion` 4 → 5 with a `migrateFromV4` that backfills `.symmetric(0)` (no fade) on every existing cue; v1, v2, and v3 chains backfill at the `LegacyCue.toCue` / `LegacyV3Cue.toCue` boundary so any pre-v5 source lands on a v5 model with valid fade data.
**Why**: Console exports (#34) need a fade-time column per cue, with split-fade syntax supported. Modelling fade as a `struct { fadeIn, fadeOut }` with synthesized Codable keeps the JSON shape stable and compile-checked, avoids a custom encoder, and makes future cue-inspector UI binding trivial (two `var` fields, two TextFields, no case rebuilding on every keystroke). An enum (`.symmetric(t)` / `.split(in:out:)`) was considered: it would encode the symmetric/split distinction at the type level rather than as a runtime equality check, but the duplication that adds (the parser already enforces parsing rules; the formatter already handles canonical output) is not worth the schema-evolution cost of custom Codable. The parser is the single gate for input validation — negative durations and malformed strings are rejected at parse time, not the struct boundary, mirroring the same trust-the-seam design we used for `Cue.cueNumber`.
**Reversal cost**: Medium. The migration is one-way (pre-v5 readers cannot open v5 files). Reverting would require a v5 → v4 down-migration that drops `fadeTime` — losing user fade data, but everything else survives.

## ADR-010 — `Cue.cueNumber` as a required model field with sort-order migration (schema v4)
**Date**: 2026-05-08
**Status**: Accepted
**Decision**: Add `Cue.cueNumber: Double` as a required user-facing cue number distinct from `Cue.id: UUID`. `addCueAtPlayhead` assigns the number by an "insert without ripple" rule: empty list → 1.0; at-end → predecessor's number + 1; between two cues → mid-point; before all → successor's number − 1 (may go negative on repeated inserts before the minimum). Bump `schemaVersion` 3 → 4 with a v3 → v4 migration that assigns sequential `cueNumber`s by time order within each item; v1 and v2 migrations chain through the same `assignCueNumbersBySort` helper so any pre-v4 source lands with valid numbers.
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
