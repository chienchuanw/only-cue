import AVFoundation
import XCTest
@testable import OnlyCue

@MainActor
final class WaveformPrewarmerTests: XCTestCase {

    func test_prewarm_populatesBucketCache_forNewItems() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }

        let bookmark = try Bookmarks.create(for: url)
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: url.lastPathComponent, kind: .audio, duration: 1, bookmarkData: bookmark),
            cues: []
        )
        let bucketMillis = WaveformPrewarmer.defaultBucketMillis

        let hash = try WaveformCache.fastFingerprint(url)
        let cacheURL = WaveformCache.shared.bucketEntryURL(assetHash: hash, bucketMillis: bucketMillis)
        try? FileManager.default.removeItem(at: cacheURL)
        XCTAssertNil(WaveformCache.shared.readBuckets(assetHash: hash, bucketMillis: bucketMillis))

        await WaveformPrewarmer.prewarm(items: [item], bucketMillis: bucketMillis)

        let cached = try XCTUnwrap(WaveformCache.shared.readBuckets(assetHash: hash, bucketMillis: bucketMillis))
        XCTAssertEqual(cached.count, 100, accuracy: 1, "1 s at 10 ms ≈ 100 buckets")
    }

    func test_prewarm_cacheHit_isANoOp() async throws {
        let url = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }

        let bookmark = try Bookmarks.create(for: url)
        let item = MediaItem(
            id: UUID(),
            media: MediaReference(displayName: url.lastPathComponent, kind: .audio, duration: 1, bookmarkData: bookmark),
            cues: []
        )
        let bucketMillis = WaveformPrewarmer.defaultBucketMillis

        await WaveformPrewarmer.prewarm(items: [item], bucketMillis: bucketMillis)

        let hash = try WaveformCache.fastFingerprint(url)
        let cacheURL = WaveformCache.shared.bucketEntryURL(assetHash: hash, bucketMillis: bucketMillis)
        let firstMtime = (try FileManager.default.attributesOfItem(atPath: cacheURL.path))[.modificationDate] as? Date

        try await Task.sleep(nanoseconds: 50_000_000)
        await WaveformPrewarmer.prewarm(items: [item], bucketMillis: bucketMillis)

        let secondMtime = (try FileManager.default.attributesOfItem(atPath: cacheURL.path))[.modificationDate] as? Date
        XCTAssertEqual(firstMtime, secondMtime, "second prewarm must not rewrite an already-cached entry")
    }
}
