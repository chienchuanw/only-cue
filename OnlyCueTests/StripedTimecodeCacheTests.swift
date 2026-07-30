import XCTest
@testable import OnlyCue

@MainActor
final class StripedTimecodeCacheTests: XCTestCase {

    private let idA = UUID()
    private let idB = UUID()

    private func track(_ start: Timecode) -> StripedTimecodeTrack? {
        StripedTimecodeTrack(anchorTimecode: start, anchorPlaybackSeconds: 0)
    }

    private var anchor: Timecode {
        guard let timecode = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25) else {
            preconditionFailure("invalid test timecode")
        }
        return timecode
    }

    func test_decodesOncePerItem_thenServesFromMemory() async {
        let cache = StripedTimecodeCache()
        var decodes = 0
        let expected = track(anchor)

        let first = await cache.track(for: idA) { decodes += 1; return expected }
        let second = await cache.track(for: idA) { decodes += 1; return expected }

        XCTAssertEqual(decodes, 1, "the second lookup must not re-read the audio")
        XCTAssertEqual(first?.anchorTimecode, anchor)
        XCTAssertEqual(second?.anchorTimecode, anchor)
    }

    // The point of the cache: "this file has no LTC" costs a full scan of every
    // channel across both windows to establish, so it has to be remembered too.
    // A cache that only stored hits would re-scan every music file on every
    // clip switch (#712).
    func test_remembersThatAFileHasNoTimecode() async {
        let cache = StripedTimecodeCache()
        var decodes = 0

        let first = await cache.track(for: idA) { decodes += 1; return nil }
        let second = await cache.track(for: idA) { decodes += 1; return nil }

        XCTAssertEqual(decodes, 1, "a known-negative must not be recomputed")
        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    func test_cachesPerItem_notGlobally() async {
        let cache = StripedTimecodeCache()
        var decodes = 0

        _ = await cache.track(for: idA) { decodes += 1; return nil }
        _ = await cache.track(for: idB) { decodes += 1; return self.track(self.anchor) }

        XCTAssertEqual(decodes, 2)
        let reread = await cache.track(for: idB) { decodes += 1; return nil }
        XCTAssertEqual(decodes, 2)
        XCTAssertEqual(reread?.anchorTimecode, anchor)
    }
}
