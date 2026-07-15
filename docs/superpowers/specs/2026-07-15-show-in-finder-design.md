# Show in Finder (media context menu) — design

**Date:** 2026-07-15
**Issue:** #636, #638 (cached-path fallback)
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
- **Locate the file (two steps, matching playback):** first resolve the
  security-scoped bookmark with `Bookmarks.resolve()` to get the file's *current*
  URL (the bookmark tracks the file across moves), confirmed with
  `FileManager.fileExists`. If that fails — the bookmark won't resolve, or the
  resolved file is gone — fall back to the path cached in the bookmark blob via
  `MediaRelocator.candidateURLs` + `firstExisting`, exactly as
  `MediaImporter.loadActive` does when it silently relinks (#587, #638). This
  keeps reveal consistent with playback: a clip that plays can always be
  revealed. (Resolve is still preferred *first* over the cached path because it
  tracks moves; the cached path is only the fallback.)
- **Reveal action:** `NSWorkspace.shared.activateFileViewerSelecting([url])`.
  Runs in the Finder process — no `startAccessingSecurityScopedResource` needed
  (that is only for reading the file's bytes).
- **File genuinely missing:** only when *both* locate steps fail (bookmark
  won't resolve *and* no cached-path candidate exists on disk) is the menu item
  **disabled** (greyed out). It does *not* route to the existing "Missing media /
  Relink media…" flow — the fallback is a *silent locate*, opening no relink
  dialog, so this stays within the grilled decision. Consistent with
  Finder/Xcode greying out Show-in-Finder when the target is truly gone.
- **No keyboard shortcut** (context-menu-only, per convention).

## Architecture

Mirrors the project's pure-core + thin-impure-boundary pattern (`Bookmarks`,
`MediaRelocator`): the "where should Finder point, and can we point there at
all" decision is a pure, unit-tested function; the one `NSWorkspace` call is the
impure boundary, verified by running the app. Reveal does **not** mutate
`ProjectModel`, so it does **not** go through `CueCommands`.

### Component (`OnlyCue/Utilities/`)

- **`MediaReveal`** — `enum` namespace, pure:
  - `static func revealURL(for media: MediaReference, fileManager: FileManager = .default, resolve: (Data) throws -> Bookmarks.Resolution = Bookmarks.resolve) -> URL?`
    - Step 1: `resolve(media.bookmarkData)`; if it succeeds *and* the URL exists
      on disk → return that URL.
    - Step 2 (on throw, or resolved-but-missing): return
      `MediaRelocator.firstExisting(MediaRelocator.candidateURLs(bookmark:displayName:))`
      — the cached-path candidate that still exists, or `nil`.
    - A `nil` return means "cannot reveal" → the menu item is disabled.
  - The `resolve` closure is injected (default `Bookmarks.resolve`), per the
    project's injectable-boundary convention (cf. #565 `UpdateChecker`), so a
    unit test can force a resolve failure and exercise the fallback.
  - A stale-but-present bookmark still returns the URL (reveal still works).

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
  - real bookmark, file moved (same dir) → returns the moved URL (resolve tracks
    the move).
  - **resolve forced to throw, but file present at the cached path (injected
    failing `resolve`) → returns the cached-path URL** (the #638 fallback branch).
  - bookmark whose file has been deleted → `nil` (both steps fail).
  - garbage / non-bookmark `Data` → `nil` (neither step can locate it).
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
