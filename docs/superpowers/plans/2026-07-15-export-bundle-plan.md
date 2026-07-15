# Export Bundle — implementation plan

**Spec:** `docs/superpowers/specs/2026-07-15-export-bundle-design.md`
**Issues:** #640 (PR1 export+schema), #641 (PR2 open end)

Two PRs, in order. Pure-core TDD; impure I/O verified by running the app.

## PR 1 — export end + schema v16

### Phase 1.1 — schema v16 (TDD)

1. **Red:** `OnlyCueTests/MediaReferenceBundlePathTests.swift`
   - `bundlePath == nil` → encoded JSON has **no** `bundlePath` key.
   - `bundlePath == "media/x.wav"` → encoded present, decodes back equal.
   - Plus `OnlyCueTests/ProjectModelMigrationV15Tests.swift`: a v15 JSON fixture
     (schemaVersion 15, a MediaReference with no bundlePath) decodes via
     `ProjectModel.decode` to schemaVersion 16, `bundlePath == nil`, other
     fields intact.
2. **Green:**
   - `MediaReference`: add `var bundlePath: String? = nil`; custom `encode(to:)`
     with `encodeIfPresent`; keep synthesized `Decodable` (add explicit
     `CodingKeys`).
   - `ProjectModel.currentSchemaVersion = 16`.
   - `ProjectModel+MigrationV15.swift` (mirror `+MigrationV14`).
   - `ProjectModel+Migration.swift` dispatch: `case 14` now migrates to 16 too
     (the chain re-stamps currentSchemaVersion, so no change needed there beyond
     adding `case 15: return try migrateFromV15(data:)`).

### Phase 1.2 — BundleLayout pure core (TDD)

3. **Red:** `OnlyCueTests/BundleLayoutTests.swift`
   - dedupe: two items, same source URL → one `media/` entry, both bundlePaths
     equal.
   - collision: two items, different URLs, same last component → `x.wav` and
     `x-2.wav`; deterministic.
   - missing: an item whose resolved URL is nil → appears in `missing`, not in
     the copy plan.
4. **Green:** `BundleLayout` pure type:
   ```
   struct BundleLayout {
       struct Entry { let source: URL; let destName: String; let itemIDs: [MediaItem.ID] }
       let entries: [Entry]                  // one per unique source, media/<destName>
       let bundlePathByItem: [MediaItem.ID: String]
       let missing: [MediaItem.ID]
       static func plan(_ resolved: [(id: MediaItem.ID, name: String, url: URL?)]) -> BundleLayout
   }
   ```

### Phase 1.3 — export action + C confirm + menu (impure; run-verified)

5. `BundleExportAction` (`OnlyCue/UI/`): resolve each item via the two-step
   locator → `BundleLayout.plan` → if `missing` non-empty show an `NSAlert`
   (Continue / Cancel) → `NSSavePanel` for destination + folder name → create
   `<name>/` + `<name>/media/`, copy entries, stamp `bundlePath` onto a model
   copy, write `<name>/<name>.cuelist` via `CueListDocument.encodeModel`.
6. Menu: add `.exportBundleRequested` notification + File-menu button in
   `AppCommands`; receive in `DocumentView`, call the action.

### Phase 1.4 — verify + PR

7. Full unit suite + SwiftLint green. Run the app: export a project, inspect the
   folder (`.cuelist` + `media/` with deduped/renamed files), confirm the C
   dialog on a deliberately-broken link.
8. PR (feat template), self-review, CI green, merge.

## PR 2 — open end (auto-attach)

9. **Spike first:** how the opened document learns its own file URL
   (`ReferenceFileDocument` → the DocumentGroup open URL). Report if blocked.
10. **TDD** pure: `(baseDir, bundlePath) -> URL?` returning the existing
    `media/` file. Wire into the media-locate path (extend the
    `MediaRelocator`/`loadActive` fallback with the doc-dir + bundlePath
    candidate), re-bookmark on hit.
11. Verify by opening an exported bundle from a fresh location; PR; review; merge.

## Out of scope

Zip output; a `.cuelistx` package; importing non-OnlyCue archives.
</content>
