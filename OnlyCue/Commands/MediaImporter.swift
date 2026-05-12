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
        let (newItems, unsupported) = await makeItems(from: urls)

        if !newItems.isEmpty {
            let firstNewID = newItems[0].id
            let documentWasEmpty = document.model.items.isEmpty
            CueCommands.addItems(newItems, to: document, undoManager: undoManager)
            if documentWasEmpty {
                CueCommands.setActiveItem(id: firstNewID, in: document)
                try await loadActive(into: document, engine: engine)
            }
            let itemsToPrewarm = newItems
            Task.detached(priority: .background) {
                await WaveformPrewarmer.prewarm(items: itemsToPrewarm)
            }
        }

        if !unsupported.isEmpty {
            throw MediaImportError.batch(unsupported: unsupported)
        }
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
        if resolution.isStale {
            let refreshed = try Bookmarks.create(for: resolution.url)
            CueCommands.refreshBookmark(itemID: item.id, to: refreshed, in: document)
        }
        await engine.load(asset: asset)
    }

    static func mediaKind(for url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        return nil
    }

    /// Decode the LTC striped onto `item`'s first audio track (resolving its
    /// security-scoped bookmark), or `nil` if there's none / the file can't be
    /// read. Used by the document window to make the SMPTE readout follow the
    /// file's own timecode.
    @MainActor
    static func stripedTimecode(for item: MediaItem?) async -> StripedTimecodeTrack? {
        guard let item else { return nil }
        do {
            let resolution = try Bookmarks.resolve(item.media.bookmarkData)
            let didAccess = resolution.url.startAccessingSecurityScopedResource()
            defer { if didAccess { resolution.url.stopAccessingSecurityScopedResource() } }
            let frames = try await LTCAudioReader.decodeTimecodes(from: resolution.url)
            return StripedTimecodeTrack(decodedFrames: frames, sampleRate: LTCAudioReader.sampleRate)
        } catch {
            return nil
        }
    }

    /// Build `MediaItem`s in parallel, preserving the original `urls` order.
    /// Asset duration loads (`.load(.duration)`) are I/O-bound, so a serial
    /// `for await` would scale linearly with N; a task group keeps wall time
    /// bounded by the slowest single item.
    @MainActor
    private static func makeItems(from urls: [URL]) async -> (items: [MediaItem], unsupported: [String]) {
        enum Outcome { case ok(MediaItem); case unsupported(String) }

        let outcomes: [Outcome] = await withTaskGroup(of: (Int, Outcome).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    do {
                        let item = try await makeItem(from: url)
                        return (index, .ok(item))
                    } catch let MediaImportError.unsupportedType(filename) {
                        return (index, .unsupported(filename))
                    } catch {
                        return (index, .unsupported(url.lastPathComponent))
                    }
                }
            }

            var collected: [Outcome?] = Array(repeating: nil, count: urls.count)
            for await (index, outcome) in group {
                collected[index] = outcome
            }
            return collected.compactMap { $0 }
        }

        var items: [MediaItem] = []
        var unsupported: [String] = []
        for outcome in outcomes {
            switch outcome {
            case .ok(let item): items.append(item)
            case .unsupported(let name): unsupported.append(name)
            }
        }
        return (items, unsupported)
    }

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
