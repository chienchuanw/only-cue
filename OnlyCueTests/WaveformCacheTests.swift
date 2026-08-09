import XCTest
@testable import OnlyCue

final class WaveformCacheTests: XCTestCase {

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

    // MARK: - Bucket cache v4 (#732)

    func test_buckets_writeThenRead_roundTrips() throws {
        let cache = makeIsolatedCache()
        let buckets = [
            WaveformBucket(peak: 0.9, rms: 0.6),
            WaveformBucket(peak: 0.2, rms: 0.1),
            WaveformBucket(peak: 1.0, rms: 0.707)
        ]

        try cache.writeBuckets(buckets, assetHash: "h", bucketMillis: 10)
        let recovered = cache.readBuckets(assetHash: "h", bucketMillis: 10)

        XCTAssertEqual(recovered, buckets)
    }

    func test_readBuckets_missing_returnsNil() {
        let cache = makeIsolatedCache()
        XCTAssertNil(cache.readBuckets(assetHash: "nope", bucketMillis: 10))
    }

    /// #715/#720 read-path guard in bucket form: the downmix, a music-only (xc1)
    /// render, and a per-channel (ch0) lane all round-trip under one hash without
    /// colliding — a music-only read must never serve the all-channel entry.
    func test_readBuckets_exclusionAndChannelKeys_roundTripWithoutCollision() throws {
        let cache = makeIsolatedCache()
        let downmix = [WaveformBucket(peak: 0.9, rms: 0.5)]
        let musicOnly = [WaveformBucket(peak: 0.4, rms: 0.2)]
        let channel0 = [WaveformBucket(peak: 0.1, rms: 0.05)]

        try cache.writeBuckets(downmix, assetHash: "h", bucketMillis: 10, excludingChannel: nil)
        try cache.writeBuckets(musicOnly, assetHash: "h", bucketMillis: 10, excludingChannel: 1)
        try cache.writeBuckets(channel0, assetHash: "h", bucketMillis: 10, channel: 0)

        XCTAssertEqual(cache.readBuckets(assetHash: "h", bucketMillis: 10, excludingChannel: nil), downmix)
        XCTAssertEqual(cache.readBuckets(assetHash: "h", bucketMillis: 10, excludingChannel: 1), musicOnly)
        XCTAssertEqual(cache.readBuckets(assetHash: "h", bucketMillis: 10, channel: 0), channel0)
    }

    /// A bucket entry stores un-normalized values verbatim — the cache must not
    /// clamp or scale (normalization is a render-time concern, #734).
    func test_buckets_storeUnnormalizedVerbatim() throws {
        let cache = makeIsolatedCache()
        let buckets = [WaveformBucket(peak: 0.25, rms: 0.18)]

        try cache.writeBuckets(buckets, assetHash: "q", bucketMillis: 10)

        XCTAssertEqual(cache.readBuckets(assetHash: "q", bucketMillis: 10)?.first, buckets.first)
    }

    func test_bucketEntryURL_differentBucketMillis_differ() {
        let cache = makeIsolatedCache()
        let ten = cache.bucketEntryURL(assetHash: "h", bucketMillis: 10, excludingChannel: nil)
        let five = cache.bucketEntryURL(assetHash: "h", bucketMillis: 5, excludingChannel: nil)
        XCTAssertNotEqual(ten, five, "bucket width is part of the key")
    }

    func test_bucketEntryURL_excludingChannel_and_channel_areDistinct() {
        let cache = makeIsolatedCache()
        let base = cache.bucketEntryURL(assetHash: "h", bucketMillis: 10, excludingChannel: nil)
        let xc1 = cache.bucketEntryURL(assetHash: "h", bucketMillis: 10, excludingChannel: 1)
        let ch1 = cache.bucketEntryURL(assetHash: "h", bucketMillis: 10, channel: 1)
        XCTAssertNotEqual(base, xc1, "music-only (xc1) must not collide with the downmix")
        XCTAssertNotEqual(base, ch1, "per-channel (ch1) must not collide with the downmix")
        XCTAssertNotEqual(xc1, ch1, "xc1 and ch1 must not collide with each other")
    }

    /// A truncated / corrupt entry (byte length not a whole number of buckets)
    /// must be treated as a miss, not decoded into garbage.
    func test_readBuckets_corruptLength_returnsNil() throws {
        let cache = makeIsolatedCache()
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        let url = cache.bucketEntryURL(assetHash: "h", bucketMillis: 10, excludingChannel: nil)
        try Data([0x01, 0x02, 0x03]).write(to: url)  // 3 bytes: not a multiple of 8

        XCTAssertNil(cache.readBuckets(assetHash: "h", bucketMillis: 10))
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
