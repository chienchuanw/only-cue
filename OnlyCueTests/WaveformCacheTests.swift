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

    private func makeIsolatedCache() -> WaveformCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-cache-test-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return WaveformCache(directory: directory)
    }
}
