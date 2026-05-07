import Foundation

enum Bookmarks {

    struct Resolution: Equatable {
        let url: URL
        let isStale: Bool
    }

    static func create(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) throws -> Resolution {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return Resolution(url: url, isStale: stale)
    }
}
