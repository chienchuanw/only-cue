import Foundation

/// Pure decision for what the Edit Media preview strip should show. Resolving
/// the bookmark here keeps the choice (and the stale/missing -> fallback rule)
/// unit-testable. Security-scoped file *access* happens later, in the subviews'
/// async loaders.
enum MediaPreviewPlan: Equatable {
    case waveform(URL)
    case poster(URL)
    case unavailable

    static func make(kind: MediaKind, bookmarkData: Data) -> Self {
        guard let resolved = try? Bookmarks.resolve(bookmarkData), !resolved.isStale else {
            return .unavailable
        }
        switch kind {
        case .audio: return .waveform(resolved.url)
        case .video: return .poster(resolved.url)
        }
    }
}
