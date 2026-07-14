# Show in Finder — implementation plan

**Spec:** `docs/superpowers/specs/2026-07-15-show-in-finder-design.md`
**Issue:** #636

Small additive feature. Pure-core + thin-impure-boundary. TDD on the pure core.

## Phase 1 — Pure core (`MediaReveal`), TDD

1. **Red:** add `OnlyCueTests/MediaRevealTests.swift`:
   - `test_revealURL_returnsURL_whenFileExists` — write a temp file, make a
     bookmark with `Bookmarks.create`, wrap in a `MediaReference`, assert
     `MediaReveal.revealURL(for:)` equals the temp file URL (compare by resolved
     path).
   - `test_revealURL_isNil_whenFileMissing` — bookmark a temp file, delete it,
     assert `nil`.
   - `test_revealURL_isNil_whenBookmarkUnresolvable` — pass a `MediaReference`
     with garbage `bookmarkData` (e.g. `Data([0x00, 0x01])`), assert `nil`.
   - Run, see the file fail to compile / tests red.
2. **Green:** add `OnlyCue/Utilities/MediaReveal.swift`:
   ```swift
   enum MediaReveal {
       static func revealURL(for media: MediaReference,
                             fileManager: FileManager = .default) -> URL? {
           guard let resolution = try? Bookmarks.resolve(media.bookmarkData) else { return nil }
           guard fileManager.fileExists(atPath: resolution.url.path) else { return nil }
           return resolution.url
       }
   }
   ```
   Run, tests green.

## Phase 2 — Wire the menu (`ItemListPane.swift`)

3. In the per-row `.contextMenu`, insert between `Edit Media…` and `Remove`:
   - `Button("Show in Finder")` → on tap, re-check `revealURL` and call
     `NSWorkspace.shared.activateFileViewerSelecting([url])`.
   - `.disabled(MediaReveal.revealURL(for: item.media) == nil)`
   - `.accessibilityIdentifier("contextMenuShowInFinder")`
   - add `Divider()` before the `Remove` button.
4. Confirm `import AppKit`/`NSWorkspace` availability (SwiftUI on macOS already
   brings AppKit; add `import AppKit` if the file lacks it).

## Phase 3 — Verify

5. `xcodegen generate` if a new source file needs to enter the project, then
   build + run the unit suite + SwiftLint; fix at root cause.
6. Manual: right-click media with a present file → Finder reveals it; delete the
   file → item greys out.

## Out of scope

- Multi-select reveal.
- Routing missing files to the Relink flow.
- Keyboard shortcut.
</content>
