import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class WaveformPrewarmerTests: XCTestCase {

    func test_prewarm_populatesCache_forNewItems() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let bookmark = try Bookmarks.create(for: url)
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: url.lastPathComponent, kind: .audio, duration: 1, bookmarkData: bookmark),
            cues: []
        )
        let resolution = WaveformPrewarmer.defaultResolution

        let hash = try WaveformCache.fileHash(url)
        let cacheURL = WaveformCache.shared.directory
            .appendingPathComponent("\(hash)-\(resolution).peaks")
        try? FileManager.default.removeItem(at: cacheURL)
        XCTAssertNil(WaveformCache.shared.read(assetHash: hash, resolution: resolution))

        await WaveformPrewarmer.prewarm(items: [item], resolution: resolution)

        let cached = try XCTUnwrap(WaveformCache.shared.read(assetHash: hash, resolution: resolution))
        XCTAssertEqual(cached.count, resolution)
    }

    func test_prewarm_cacheHit_isANoOp() async throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let bookmark = try Bookmarks.create(for: url)
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: url.lastPathComponent, kind: .audio, duration: 1, bookmarkData: bookmark),
            cues: []
        )
        let resolution = WaveformPrewarmer.defaultResolution

        await WaveformPrewarmer.prewarm(items: [item], resolution: resolution)

        let hash = try WaveformCache.fileHash(url)
        let cacheURL = WaveformCache.shared.directory
            .appendingPathComponent("\(hash)-\(resolution).peaks")
        let firstMtime = (try FileManager.default.attributesOfItem(atPath: cacheURL.path))[.modificationDate] as? Date

        try await Task.sleep(nanoseconds: 50_000_000)
        await WaveformPrewarmer.prewarm(items: [item], resolution: resolution)

        let secondMtime = (try FileManager.default.attributesOfItem(atPath: cacheURL.path))[.modificationDate] as? Date
        XCTAssertEqual(firstMtime, secondMtime, "second prewarm must not rewrite an already-cached entry")
    }
}
