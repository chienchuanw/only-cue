import AppKit

/// One row on the welcome window's recent-projects list (#591).
struct RecentProject: Identifiable, Equatable {
    let url: URL
    let name: String
    let folder: String
    let date: Date?
    let exists: Bool

    var id: URL { url }
}

/// Maps `NSDocumentController` recent-document URLs to displayable rows, and
/// computes recents-list edits. The mapping is pure (FileManager-injectable) so
/// it is unit-tested without the document controller.
enum RecentProjectsModel {

    /// Map a newest-first URL list to rows, preserving order. A URL whose file
    /// is gone is still returned (greyed/removable in the UI).
    static func recents(from urls: [URL], fileManager: FileManager = .default) -> [RecentProject] {
        urls.map { url in
            let exists = fileManager.fileExists(atPath: url.path)
            let date = exists
                ? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                : nil
            let parent = url.deletingLastPathComponent().path
            return RecentProject(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                folder: (parent as NSString).abbreviatingWithTildeInPath,
                date: date,
                exists: exists
            )
        }
    }

    /// The newest-first URL list with `url` removed (used by the remove flow,
    /// since `NSDocumentController` has no public single-URL removal).
    static func removing(_ url: URL, from urls: [URL]) -> [URL] {
        urls.filter { $0 != url }
    }

    /// The live recents from `NSDocumentController` (impure read).
    @MainActor
    static func load() -> [RecentProject] {
        recents(from: NSDocumentController.shared.recentDocumentURLs)
    }
}
