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

    // MARK: - fast fingerprint (#731)

    func test_fastFingerprint_isStableForSameContents() throws {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try WaveformCache.fastFingerprint(url)
        let second = try WaveformCache.fastFingerprint(url)

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func test_fastFingerprint_differsAcrossDifferentContents() throws {
        let urlA = try SilentAudioFixture.makeWAV(duration: 1)
        let urlB = try SilentAudioFixture.makeSineWAV(duration: 1, frequency: 440)
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        let hashA = try WaveformCache.fastFingerprint(urlA)
        let hashB = try WaveformCache.fastFingerprint(urlB)

        XCTAssertNotEqual(hashA, hashB)
    }

    /// The fingerprint must not depend on filesystem metadata like mtime — a
    /// `touch` that leaves content unchanged must not invalidate the cache
    /// (spec §1: "內容沒變不該重算").
    func test_fastFingerprint_independentOfModificationTime() throws {
        let url = try makeRawFile(bytes: Data((0..<4096).map { UInt8($0 & 0xFF) }))
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try WaveformCache.fastFingerprint(url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: url.path
        )
        let after = try WaveformCache.fastFingerprint(url)

        XCTAssertEqual(before, after, "fingerprint must not depend on mtime")
    }

    /// Documents the deliberately-accepted tradeoff (spec §1): the fingerprint
    /// hashes only the head and tail, so two large files with identical size and
    /// identical first/last 1MB but a differing middle collide. This both proves
    /// the read is constant-time (head+tail only, never the middle) and pins the
    /// accepted false-hit that the user signed off on (no "regenerate" escape).
    func test_fastFingerprint_ignoresMiddleBytes() throws {
        let urlA = try makeRawFile(bytes: headMiddleTail(middle: 0xAA))
        let urlB = try makeRawFile(bytes: headMiddleTail(middle: 0xBB))
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        XCTAssertEqual(
            try WaveformCache.fastFingerprint(urlA),
            try WaveformCache.fastFingerprint(urlB),
            "only head+tail are hashed, so a middle-only difference collides by design"
        )
    }

    /// File size is part of the key: two files with identical head and tail but
    /// different total length must not collide.
    func test_fastFingerprint_differsWhenSizeDiffers() throws {
        let chunk = 1 << 20
        let urlA = try makeRawFile(bytes: headMiddleTail(middle: 0x00, middleCount: chunk))
        let urlB = try makeRawFile(bytes: headMiddleTail(middle: 0x00, middleCount: 2 * chunk))
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        XCTAssertNotEqual(
            try WaveformCache.fastFingerprint(urlA),
            try WaveformCache.fastFingerprint(urlB),
            "file size must be part of the fingerprint"
        )
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

    /// #720 bug ①: guard the exact collision that would show all-channel data on a
    /// music-only read — a write under `excludingChannel: 1` must be UNREADABLE
    /// under `excludingChannel: nil` (and vice-versa), not merely a different URL.
    /// Without this, the container's music-only read could serve a stale
    /// all-channel entry and the waveform would still look like LTC.
    func test_read_underOtherExclusionKey_returnsNil() throws {
        let cache = makeIsolatedCache()

        try cache.write([0.2, 0.4, 0.6], assetHash: "abc", resolution: 3, excludingChannel: 1)
        XCTAssertNil(
            cache.read(assetHash: "abc", resolution: 3, excludingChannel: nil),
            "a music-only (xc1) write must not be readable as an all-channel entry"
        )

        try cache.write([0.1, 0.5, 0.9], assetHash: "def", resolution: 3, excludingChannel: nil)
        XCTAssertNil(
            cache.read(assetHash: "def", resolution: 3, excludingChannel: 1),
            "an all-channel write must not be readable as a music-only (xc1) entry"
        )
    }

    // MARK: - Per-channel cache keys (#720)

    func test_perChannel_writeThenRead_roundTripsEachChannel() throws {
        let cache = makeIsolatedCache()
        let ch0Peaks: [Float] = [0.1, 0.2, 0.3]
        let ch1Peaks: [Float] = [0.7, 0.8, 0.9]

        try cache.write(ch0Peaks, assetHash: "abc", resolution: 3, channel: 0)
        try cache.write(ch1Peaks, assetHash: "abc", resolution: 3, channel: 1)

        let recoveredCh0 = cache.read(assetHash: "abc", resolution: 3, channel: 0)
        let recoveredCh1 = cache.read(assetHash: "abc", resolution: 3, channel: 1)

        XCTAssertEqual(recoveredCh0, ch0Peaks, "channel 0 peaks should round-trip")
        XCTAssertEqual(recoveredCh1, ch1Peaks, "channel 1 peaks should round-trip")
        XCTAssertNotEqual(recoveredCh0, recoveredCh1, "channel 0 and channel 1 entries must be distinct")
    }

    func test_perChannel_doesNotCollideWithCombinedEntry() throws {
        let cache = makeIsolatedCache()
        let combinedPeaks: [Float] = [0.0, 0.5, 1.0]
        let ch0Peaks: [Float] = [0.1, 0.2, 0.3]

        try cache.write(combinedPeaks, assetHash: "abc", resolution: 3)
        try cache.write(ch0Peaks, assetHash: "abc", resolution: 3, channel: 0)

        XCTAssertEqual(
            cache.read(assetHash: "abc", resolution: 3),
            combinedPeaks,
            "combined entry must not be overwritten by channel 0"
        )
        XCTAssertEqual(
            cache.read(assetHash: "abc", resolution: 3, channel: 0),
            ch0Peaks,
            "channel 0 entry must not be overwritten by combined"
        )
    }

    func test_perChannel_doesNotCollideWithExcludingChannelEntry() {
        let cache = makeIsolatedCache()
        let channelURL = cache.entryURL(assetHash: "abc", resolution: 32, channel: 0)
        let excludingURL = cache.entryURL(assetHash: "abc", resolution: 32, excludingChannel: 0)
        let combinedURL = cache.entryURL(assetHash: "abc", resolution: 32)
        XCTAssertNotEqual(
            channelURL,
            excludingURL,
            "channel: 0 key must not collide with excludingChannel: 0 key"
        )
        XCTAssertNotEqual(
            channelURL,
            combinedURL,
            "channel: 0 key must not collide with combined key"
        )
    }

    private func makeIsolatedCache() -> WaveformCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-cache-test-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return WaveformCache(directory: directory)
    }

    /// Writes `bytes` to a fresh temp file and returns its URL.
    private func makeRawFile(bytes: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fingerprint-test-\(UUID().uuidString).bin")
        try bytes.write(to: url)
        return url
    }

    /// A blob larger than 2× the 1MB fingerprint chunk, so the fingerprint takes
    /// its head/tail path: a fixed 1MB head, a `middle`-filled body of
    /// `middleCount` bytes, and a fixed 1MB tail. Varying `middle` changes only
    /// the ignored region; varying `middleCount` changes the total size.
    private func headMiddleTail(middle: UInt8, middleCount: Int = 1 << 20) -> Data {
        let chunk = 1 << 20
        var data = Data(repeating: 0x01, count: chunk)
        data.append(Data(repeating: middle, count: middleCount))
        data.append(Data(repeating: 0x02, count: chunk))
        return data
    }
}
