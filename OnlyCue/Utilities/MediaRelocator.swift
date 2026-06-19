import Foundation

/// Recovers a media file's location when its security-scoped bookmark won't
/// resolve but the file is still on disk — e.g. a project saved by an older
/// OnlyCue, or opened on a different install, with the media still in its
/// original directory (#587).
///
/// The original absolute path is already cached inside every `MediaReference`
/// bookmark blob, so it can be read with `URL.resourceValues(forKeys:
/// fromBookmarkData:)` WITHOUT resolving security scope and WITHOUT the file
/// needing to exist. That means no schema change and full retroactivity for
/// already-saved documents. See ADR-006 for the bookmark-based reference model.
enum MediaRelocator {

    /// The absolute path stored in the bookmark blob, or `nil` if the data is
    /// not a readable bookmark.
    static func cachedPath(fromBookmark data: Data) -> String? {
        URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data)?.path
    }

    /// Places to look for the file when the bookmark fails: its exact saved
    /// path, and the same directory paired with the known display name (covers
    /// a bookmark whose cached name drifts from `displayName`). De-duplicated.
    static func candidateURLs(bookmark: Data, displayName: String) -> [URL] {
        guard let path = cachedPath(fromBookmark: bookmark) else { return [] }
        let cached = URL(fileURLWithPath: path)
        let sameDirectory = cached.deletingLastPathComponent().appendingPathComponent(displayName)
        return cached == sameDirectory ? [cached] : [cached, sameDirectory]
    }

    /// The first candidate that exists on disk, or `nil` if none do.
    static func firstExisting(_ urls: [URL], fileManager: FileManager = .default) -> URL? {
        urls.first { fileManager.fileExists(atPath: $0.path) }
    }
}
