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

    // The key is the item id, which survives a relink — the user can point the
    // same item at a different file, and a remembered "no LTC" would otherwise
    // outlive the file it was true of (#712).
    func test_invalidate_forcesARescanForThatItemOnly() async {
        let cache = StripedTimecodeCache()
        var decodes = 0

        _ = await cache.track(for: idA) { decodes += 1; return nil }
        _ = await cache.track(for: idB) { decodes += 1; return nil }
        cache.invalidate(idA)

        let rescanned = await cache.track(for: idA) { decodes += 1; return self.track(self.anchor) }
        XCTAssertEqual(rescanned?.anchorTimecode, anchor, "the relinked file's LTC must be found")
        _ = await cache.track(for: idB) { decodes += 1; return nil }
        XCTAssertEqual(decodes, 3, "only the invalidated item re-decodes")
    }

    // A cancelled scan reports whatever it had reached, which is not an answer
    // about the file — caching it would mislabel that file for the whole run.
    func test_doesNotRememberTheResultOfACancelledScan() async {
        let cache = StripedTimecodeCache()
        var decodes = 0

        // The body can't start until this actor suspends at `await`, so the
        // cancel is guaranteed to land first.
        let task = Task { await cache.track(for: self.idA) { decodes += 1; return nil } }
        task.cancel()
        _ = await task.value

        _ = await cache.track(for: idA) { decodes += 1; return self.track(self.anchor) }
        XCTAssertEqual(decodes, 2, "the cancelled scan's answer must not have been stored")
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
