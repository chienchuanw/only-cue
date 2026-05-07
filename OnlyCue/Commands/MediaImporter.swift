import AVFoundation
import UniformTypeIdentifiers

enum MediaImportError: Error, Equatable {
    case unsupportedType(filename: String)
}

enum MediaImporter {

    static let allowedContentTypes: [UTType] = [.audio, .movie]

    @MainActor
    static func importMedia(
        from url: URL,
        into document: CueListDocument,
        engine: PlayerEngine
    ) async throws {
        guard let kind = mediaKind(for: url) else {
            throw MediaImportError.unsupportedType(filename: url.lastPathComponent)
        }
        let bookmark = try Bookmarks.create(for: url)
        let asset = AVURLAsset(url: url)
        let cmDuration = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(cmDuration)
        document.model.media = MediaReference(
            displayName: url.lastPathComponent,
            kind: kind,
            duration: duration,
            bookmarkData: bookmark
        )
        await engine.load(asset: asset)
    }

    @MainActor
    static func reload(
        into document: CueListDocument,
        engine: PlayerEngine
    ) async throws {
        guard let media = document.model.media else { return }
        let resolution = try Bookmarks.resolve(media.bookmarkData)
        let asset = AVURLAsset(url: resolution.url)
        _ = try await asset.load(.duration)
        if resolution.isStale {
            let refreshed = try Bookmarks.create(for: resolution.url)
            document.model.media?.bookmarkData = refreshed
        }
        await engine.load(asset: asset)
    }

    static func mediaKind(for url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        return nil
    }
}
