# Export Bundle — design

**Date:** 2026-07-15
**Issues:** #640 (export end + schema v16), #641 (open end)
**Status:** Approved (grilling)

## Goal

Let a user collect a project **and all the audio it references** into one
self-contained **folder** they can hand to someone else. On the other machine,
opening the `.cuelist` inside that folder just works — **no relink**.

## Decisions (locked with the user)

- **Shape = a plain folder (not a package, not a new document type).** Export
  produces:
  ```
  My Show/
  ├── My Show.cuelist      # ordinary .cuelist — format unchanged bar one optional field
  └── media/               # every referenced audio file, original filenames
      ├── Intro.wav
      └── Finale.mp3
  ```
  `.cuelist` stays the **primary working format**; the bundle is just "a
  `.cuelist` plus its audio, gathered into a folder". The recipient opens the
  **ordinary `.cuelist`** — no `.cuelistx`, no package UTType, no new document
  type. This is the direction ADR-006 pre-authorised ("add a self-contained
  bundle format alongside").
- **Auto-attach mechanism (the no-relink core):** schema **v15 → v16** adds an
  optional `MediaReference.bundlePath` (e.g. `"media/Intro.wav"`). On open,
  media is located the existing two ways first (resolve bookmark, then cached
  path); if both fail, use `bundlePath` **relative to the `.cuelist`'s own
  directory** to find the file in `media/`, attach it, and re-bookmark to the
  local path (same as today's `autoRelinkActive`). `bundlePath` is the
  authoritative fallback; the stored bookmark is just a cache.
- **`.cuelist` byte-compatibility:** `bundlePath` is optional and encoded with
  `encodeIfPresent`, so a normal working `.cuelist` (no bundle) is **unchanged**
  — the key is simply absent. Only a bundle's `.cuelist` carries it.
- **Export scope:** the **whole project** (all media items). Single-song export
  is already `.occues`.
- **Dedupe & collisions:** the same source file referenced by several items is
  copied **once**; two different files sharing a name are auto-renamed
  (`track.wav`, `track-2.wav`) and disambiguated by `bundlePath`.
- **Broken links (option C):** if a media file can't be located at export time
  (both locate steps fail), warn **before** writing — list the N files that
  can't be included ("the recipient will need to relink these") and let the user
  **Continue (skip them)** or **Cancel**. When everything resolves, export runs
  with no prompt.
- **Product = a folder** (no zip; zip is a possible future add-on).
- The bundle's `.cuelist` keeps each item's original bookmark as-is (a cache);
  `bundlePath` is authoritative for recipients.

## Architecture

Pure-core + thin-impure-boundary, matching the project's exporters
(`CueCSVExporter`, `CueListTransfer`) and the two-step media locator from
`MediaRelocator`/`MediaReveal` (#636/#638).

### Delivery: two PRs, in order

Both must land for the feature to be "done"; each is independently useful and
reviewable.

#### PR 1 — export end + schema v16

- **Schema v16** (`OnlyCue/Document/`):
  - `MediaReference` gains `var bundlePath: String? = nil`. The memberwise init
    keeps its existing call-sites working (defaulted). Custom `encode(to:)` uses
    `encodeIfPresent(bundlePath)` so a `nil` omits the key entirely (synthesized
    encoding would emit `"bundlePath": null` and perturb every existing file).
    `Decodable` stays synthesized (optional missing key → `nil`).
  - `ProjectModel.currentSchemaVersion` → `16`.
  - `ProjectModel+MigrationV15.swift`: `migrateFromV15(data:)` decodes a
    `LegacyV15` snapshot and forwards every field, re-stamping
    `schemaVersion = 16` (mirrors `migrateFromV14`). `items: [MediaItem]` works
    directly because the only change is an optional field (missing → nil).
  - `decode(from:)` dispatch gains `case 15: return try migrateFromV15(data:)`.
- **`BundleLayout` — pure** (`OnlyCue/Commands/` or `Utilities/`):
  - Input: the ordered media items, each tagged with whether/where its source
    file resolved (a `URL?` per item — the impure caller resolves first).
  - Output: a plan — for each **resolvable** source URL, the deduped `media/`
    destination filename (collision-renamed) and the `bundlePath` string; plus
    the list of items whose file is **missing** (for the option-C warning).
  - Pure and fully unit-tested: dedupe by source URL, deterministic collision
    renaming, `bundlePath` assignment, missing-list.
- **`BundleExportAction` — impure shell** (`OnlyCue/UI/`): resolve each item's
  URL (two-step locator), run `BundleLayout`, show the option-C confirm if
  anything is missing, then create `dest/<name>/`, copy files into `media/`,
  write the `.cuelist` (model with `bundlePath` stamped per item) via
  `CueListDocument.encodeModel`. Uses `NSSavePanel` for destination + folder
  name. Not unit-tested (thin I/O).
- **Menu:** File menu **"Export Bundle…"**, via the existing
  `NotificationCenter` → `DocumentView` receiver → action pattern (like
  `.exportCueListRequested`).

#### PR 2 — open end (auto-attach)

- When opening a `.cuelist`, if the two-step locator fails for an item and the
  item has a `bundlePath`, resolve it against the **`.cuelist`'s directory**
  (`<docDir>/media/<name>`); if the file exists, attach + re-bookmark.
- **Known risk to resolve in PR2's plan:** `ReferenceFileDocument` doesn't hand
  the model its own file URL. PR2 must find the seam (the document's open URL
  from `DocumentGroup`/the file-open path) to know `<docDir>`. Spike this first;
  report if blocked. Does not affect PR1.
- Pure resolution (bundlePath + a supplied base directory → candidate URL) is
  unit-tested; the wiring that supplies the real doc directory is the impure part.

## Testing

- **Schema (unit):** a `MediaReference` with `bundlePath == nil` round-trips
  with the key absent from JSON; with a value, it round-trips present. A v15
  fixture decodes to v16 with `bundlePath == nil` and every other field intact.
- **`BundleLayout` (unit):** dedupe (same URL twice → one copy, both items point
  at it), collision rename (two different files, same name → `x.wav`/`x-2.wav`),
  `bundlePath` values, missing-list for unresolved items.
- **Open end (unit, PR2):** given a base dir + `bundlePath`, returns the
  existing `media/` URL, else nil.
- **Not unit-tested:** `NSSavePanel`, file copying, folder writing — verified by
  running the app (export a project, inspect the folder, open it on-path).

## Hard-rules check

Schema bump v16 **with** a migration ✓. No App Sandbox (ADR-007) — full file
access for copy/write ✓. `.cuelist` on-disk format unchanged for non-bundle
files (optional key omitted) ✓. No embedded media in `.cuelist` — the bundle is
a separate folder artifact, ADR-006's pre-authorised direction ✓. macOS 14.0
floor untouched ✓.
</content>
