import Foundation

/// #636 — the "Show in Finder" media context-menu action. Locates a media file
/// the same two ways playback does (`MediaImporter.loadActive`), so a clip that
/// plays can always be revealed:
///   1. resolve the security-scoped bookmark to the file's *current* URL (the
///      bookmark tracks the file across moves) and confirm it exists;
///   2. failing that, fall back to the path cached in the bookmark blob
///      (`MediaRelocator`), covering a bookmark that won't resolve in this
///      context — e.g. a project opened on another install — while the file is
///      still at its saved path (#587, #638).
///
/// Pure and unit-tested: `nil` means the file can't be located either way, so
/// the menu item is disabled. The actual `NSWorkspace` reveal is a thin impure
/// shell at the call site. Revealing does not read the file's bytes, so no
/// security-scoped access needs to be started.
enum MediaReveal {

    /// The on-disk URL to select in Finder for `media`, or `nil` when neither
    /// bookmark resolution nor the cached-path fallback finds an existing file.
    ///
    /// `resolve` is injected (default `Bookmarks.resolve`) so tests can force a
    /// resolution failure and exercise the fallback.
    static func revealURL(for media: MediaReference,
                          fileManager: FileManager = .default,
                          resolve: (Data) throws -> Bookmarks.Resolution = Bookmarks.resolve) -> URL? {
        if let resolution = try? resolve(media.bookmarkData),
           fileManager.fileExists(atPath: resolution.url.path) {
            return resolution.url
        }
        let candidates = MediaRelocator.candidateURLs(
            bookmark: media.bookmarkData,
            displayName: media.displayName
        )
        return MediaRelocator.firstExisting(candidates, fileManager: fileManager)
    }
}
