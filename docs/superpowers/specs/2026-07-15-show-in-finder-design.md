# Show in Finder (media context menu) — design

**Date:** 2026-07-15
**Issue:** #636
**Status:** Approved (grilling)

## Goal

Add a **Show in Finder** item to the right-click context menu on each media row
in the left-side Media pane (`ItemListPane`), so a user can jump straight to
where that media file actually lives on disk. Reveals the single right-clicked
media; disabled when the file cannot currently be located.

## Decisions (locked with the user)

- **Label:** `Show in Finder` (English, matching the existing menu and the
  Apple-native convention: Safari downloads, Xcode).
- **Menu order** in `ItemListPane` `.contextMenu`:
  `Edit Media…` → `Show in Finder` → `Divider()` → `Remove`. The divider is new
  — it separates the destructive `Remove` from the rest (currently `Remove`
  abuts `Edit Media…`).
- **Scope:** operates on the single right-clicked media, like the existing
  `Edit Media…` / `Remove` items. No multi-select reveal.
- **Locate the file:** resolve the security-scoped bookmark with
  `Bookmarks.resolve()` to get the file's *current* URL (the bookmark tracks the
  file across moves), then confirm with `FileManager.fileExists`. Reveal the
  resolved URL. This is deliberately preferred over `MediaRelocator.cachedPath`
  (the bookmark's cached path), which would point at the pre-move location.
- **Reveal action:** `NSWorkspace.shared.activateFileViewerSelecting([url])`.
  Runs in the Finder process — no `startAccessingSecurityScopedResource` needed
  (that is only for reading the file's bytes).
- **Missing / unresolvable file:** the menu item is **disabled** (greyed out).
  It does *not* route to the existing "Missing media / Relink media…" flow —
  that coupling is out of scope. Consistent with Finder/Xcode greying out
  Show-in-Finder when the target is gone.
- **No keyboard shortcut** (context-menu-only, per convention).

## Architecture

Mirrors the project's pure-core + thin-impure-boundary pattern (`Bookmarks`,
`MediaRelocator`): the "where should Finder point, and can we point there at
all" decision is a pure, unit-tested function; the one `NSWorkspace` call is the
impure boundary, verified by running the app. Reveal does **not** mutate
`ProjectModel`, so it does **not** go through `CueCommands`.

### Component (`OnlyCue/Utilities/`)

- **`MediaReveal`** — `enum` namespace, pure:
  - `static func revealURL(for media: MediaReference, fileManager: FileManager = .default) -> URL?`
    - Resolves `media.bookmarkData` via `Bookmarks.resolve`. On throw → `nil`.
    - If the resolved URL's path does not exist on disk → `nil`.
    - Otherwise → the resolved `URL`.
    - A `nil` return means "cannot reveal" → the menu item is disabled.
  - A stale-but-present bookmark still returns the URL (reveal still works); only
    an outright resolve failure or a missing file returns `nil`.

### Wiring (`OnlyCue/UI/ItemListPane.swift`)

Inside the existing per-row `.contextMenu`, between `Edit Media…` and `Remove`:

```swift
Button("Show in Finder") {
    if let url = MediaReveal.revealURL(for: item.media) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
.disabled(MediaReveal.revealURL(for: item.media) == nil)
.accessibilityIdentifier("contextMenuShowInFinder")

Divider()
```

The `Button` closure re-checks `revealURL` so a file removed between menu-open
and click is a no-op rather than a stale reveal.

## Testing

- **Unit (`OnlyCueTests/MediaRevealTests.swift`), TDD red → green:**
  - real temp file + real bookmark (`Bookmarks.create`) → `revealURL` returns
    that file's URL.
  - bookmark whose file has been deleted → `nil` (file-missing branch).
  - garbage / non-bookmark `Data` → `nil` (resolve-failure branch).
- **Not unit-tested:** the `NSWorkspace.activateFileViewerSelecting` call (thin
  impure shell) — verified by running the app.
- **Manual verification:** right-click a media whose file exists → Finder opens
  with it selected; move/delete the file → the item greys out.

## Hard-rules check

No `ProjectModel` schema change (no `schemaVersion` bump). No App Sandbox
entitlement. No embedded media. macOS 14.0 floor untouched. Pure additive
change.
</content>
</invoke>
