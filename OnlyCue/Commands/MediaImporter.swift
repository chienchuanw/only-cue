import AVFoundation
import UniformTypeIdentifiers

enum MediaImportError: Error, Equatable {
    case unsupportedType(filename: String)
    case batch(unsupported: [String])
}

enum MediaImporter {

    static let allowedContentTypes: [UTType] = [.audio, .movie]

    @MainActor
    static func importMedia(
        from urls: [URL],
        into document: CueListDocument,
        engine: PlayerEngine,
        undoManager: UndoManager? = nil
    ) async throws {
        var newItems: [MediaItem] = []
        var unsupported: [String] = []

        for url in urls {
            do {
                newItems.append(try await makeItem(from: url))
            } catch let MediaImportError.unsupportedType(filename) {
                unsupported.append(filename)
            }
        }

        if !newItems.isEmpty {
            let firstNewID = newItems.first!.id
            let documentWasEmpty = document.model.items.isEmpty
            CueCommands.addItems(newItems, to: document, undoManager: undoManager)
            if documentWasEmpty {
                CueCommands.setActiveItem(id: firstNewID, in: document)
                try await loadActive(into: document, engine: engine)
            }
        }

        if !unsupported.isEmpty {
            throw MediaImportError.batch(unsupported: unsupported)
        }
    }

    @MainActor
    static func importMedia(
        from url: URL,
        into document: CueListDocument,
        engine: PlayerEngine
    ) async throws {
        try await importMedia(from: [url], into: document, engine: engine)
    }

    @MainActor
    static func loadActive(
        into document: CueListDocument,
        engine: PlayerEngine
    ) async throws {
        guard let item = document.model.activeItem else {
            await engine.unload()
            return
        }
        let resolution = try Bookmarks.resolve(item.media.bookmarkData)
        let asset = AVURLAsset(url: resolution.url)
        _ = try await asset.load(.duration)
        if resolution.isStale, let index = document.model.activeItemIndex {
            let refreshed = try Bookmarks.create(for: resolution.url)
            document.model.items[index].media.bookmarkData = refreshed
        }
        await engine.load(asset: asset)
    }

    @MainActor
    static func reload(
        into document: CueListDocument,
        engine: PlayerEngine
    ) async throws {
        try await loadActive(into: document, engine: engine)
    }

    static func mediaKind(for url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        return nil
    }

    @MainActor
    private static func makeItem(from url: URL) async throws -> MediaItem {
        guard let kind = mediaKind(for: url) else {
            throw MediaImportError.unsupportedType(filename: url.lastPathComponent)
        }
        let bookmark = try Bookmarks.create(for: url)
        let asset = AVURLAsset(url: url)
        let cmDuration = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(cmDuration)
        let media = MediaReference(
            displayName: url.lastPathComponent,
            kind: kind,
            duration: duration,
            bookmarkData: bookmark
        )
        return MediaItem(id: UUID(), media: media, cues: [])
    }
}
