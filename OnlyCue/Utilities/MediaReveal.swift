import Foundation

/// #636 — the "Show in Finder" media context-menu action. Resolves a media's
/// security-scoped bookmark to the file's *current* on-disk URL (the bookmark
/// tracks the file across moves, unlike `MediaRelocator.cachedPath`, which
/// reports the pre-move path) and confirms the file still exists.
///
/// Pure and unit-tested: `nil` means the file can't be located right now, so
/// the menu item is disabled. The actual `NSWorkspace` reveal is a thin impure
/// shell at the call site. Revealing does not read the file's bytes, so no
/// security-scoped access needs to be started.
enum MediaReveal {

    /// The on-disk URL to select in Finder for `media`, or `nil` when the
    /// bookmark won't resolve or the resolved file no longer exists.
    static func revealURL(for media: MediaReference,
                          fileManager: FileManager = .default) -> URL? {
        guard let resolution = try? Bookmarks.resolve(media.bookmarkData) else { return nil }
        guard fileManager.fileExists(atPath: resolution.url.path) else { return nil }
        return resolution.url
    }
}
