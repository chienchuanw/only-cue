import XCTest
@testable import OnlyCue

final class WaveformCacheTests: XCTestCase {

    func test_writeThenRead_roundTripsPeaks() throws {
        let cache = makeIsolatedCache()
        let peaks: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]

        try cache.write(peaks, assetHash: "abc123", resolution: 5)
        let recovered = cache.read(assetHash: "abc123", resolution: 5)

        XCTAssertEqual(recovered, peaks)
    }

    func test_read_missingEntry_returnsNil() {
        let cache = makeIsolatedCache()
        XCTAssertNil(cache.read(assetHash: "nope", resolution: 32))
    }

    func test_read_resolutionMismatch_returnsNil() throws {
        let cache = makeIsolatedCache()
        try cache.write([0.1, 0.2, 0.3], assetHash: "h1", resolution: 3)

        XCTAssertNil(cache.read(assetHash: "h1", resolution: 4))
    }

    func test_fileHash_isStableForSameContents() throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try WaveformCache.fileHash(url)
        let second = try WaveformCache.fileHash(url)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func test_fileHash_differsAcrossDifferentContents() throws {
        let urlA = try SilentAudioFixture.makeWAV(duration: 1)
        let urlB = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        let hashA = try WaveformCache.fileHash(urlA)
        let hashB = try WaveformCache.fileHash(urlB)

        XCTAssertNotEqual(hashA, hashB)
    }

    // MARK: - Channel exclusion cache keys (#715)

    func test_entryURL_withExcludedChannel_differsFromDefaultKey() {
        let cache = makeIsolatedCache()
        let defaultURL = cache.entryURL(assetHash: "abc", resolution: 32, excludingChannel: nil)
        let musicOnlyURL = cache.entryURL(assetHash: "abc", resolution: 32, excludingChannel: 1)
        XCTAssertNotEqual(
            defaultURL,
            musicOnlyURL,
            "music-only render (excludingChannel: 1) must not collide with all-channel render"
        )
    }

    func test_entryURL_sameExcludedChannel_isStable() {
        let cache = makeIsolatedCache()
        let urlFirst = cache.entryURL(assetHash: "abc", resolution: 32, excludingChannel: 1)
        let urlSecond = cache.entryURL(assetHash: "abc", resolution: 32, excludingChannel: 1)
        XCTAssertEqual(urlFirst, urlSecond, "same exclusion must produce the same cache URL (no collision)")
    }

    func test_entryURL_differentExcludedChannels_differ() {
        let cache = makeIsolatedCache()
        let ch1 = cache.entryURL(assetHash: "abc", resolution: 32, excludingChannel: 1)
        let ch0 = cache.entryURL(assetHash: "abc", resolution: 32, excludingChannel: 0)
        XCTAssertNotEqual(ch1, ch0, "excluding ch0 vs ch1 must produce different cache keys")
    }

    func test_writeThenRead_withExcludedChannel_roundTrips() throws {
        let cache = makeIsolatedCache()
        let peaks: [Float] = [0.1, 0.9, 0.5]

        try cache.write(peaks, assetHash: "xyz", resolution: 3, excludingChannel: 1)
        let recovered = cache.read(assetHash: "xyz", resolution: 3, excludingChannel: 1)

        XCTAssertEqual(recovered, peaks)
    }

    func test_writeThenRead_excludedChannelDoesNotCollideWithDefault() throws {
        let cache = makeIsolatedCache()
        let defaultPeaks: [Float] = [0.0, 0.5, 1.0]
        let musicPeaks: [Float] = [0.2, 0.4, 0.6]

        try cache.write(defaultPeaks, assetHash: "xyz", resolution: 3, excludingChannel: nil)
        try cache.write(musicPeaks, assetHash: "xyz", resolution: 3, excludingChannel: 1)

        XCTAssertEqual(cache.read(assetHash: "xyz", resolution: 3, excludingChannel: nil), defaultPeaks)
        XCTAssertEqual(cache.read(assetHash: "xyz", resolution: 3, excludingChannel: 1), musicPeaks)
    }

    private func makeIsolatedCache() -> WaveformCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-cache-test-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return WaveformCache(directory: directory)
    }
}
