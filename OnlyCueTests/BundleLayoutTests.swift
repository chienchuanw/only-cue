import XCTest
@testable import OnlyCue

/// #640 — `BundleLayout` is the pure core of Export Bundle: given each media
/// item's resolved source URL (nil = couldn't locate), it plans the `media/`
/// folder — deduping shared files, renaming name collisions deterministically,
/// assigning each item its `bundlePath`, and listing the unresolved items for
/// the option-C warning.
final class BundleLayoutTests: XCTestCase {

    private func src(_ name: String, _ url: URL?, id: UUID = UUID()) -> BundleLayout.Source {
        BundleLayout.Source(id: id, name: name, url: url)
    }

    func test_dedupe_sameSourceCopiedOnce() {
        let shared = URL(fileURLWithPath: "/a/song.wav")
        let a = src("song.wav", shared)
        let b = src("song.wav", shared)

        let layout = BundleLayout.plan([a, b])

        XCTAssertEqual(layout.entries.count, 1)
        XCTAssertEqual(layout.entries[0].itemIDs.count, 2)
        XCTAssertEqual(layout.bundlePathByItem[a.id], "media/song.wav")
        XCTAssertEqual(layout.bundlePathByItem[b.id], "media/song.wav")
    }

    func test_collision_differentSourcesSameNameRenamed() {
        let a = src("track.wav", URL(fileURLWithPath: "/a/track.wav"))
        let b = src("track.wav", URL(fileURLWithPath: "/b/track.wav"))

        let layout = BundleLayout.plan([a, b])

        XCTAssertEqual(layout.entries.count, 2)
        XCTAssertEqual(layout.bundlePathByItem[a.id], "media/track.wav")
        XCTAssertEqual(layout.bundlePathByItem[b.id], "media/track-2.wav")
    }

    func test_missing_unresolvedItemsListedNotCopied() {
        let ok = src("ok.wav", URL(fileURLWithPath: "/a/ok.wav"))
        let gone = src("gone.wav", nil)

        let layout = BundleLayout.plan([ok, gone])

        XCTAssertEqual(layout.missing, [gone.id])
        XCTAssertEqual(layout.entries.count, 1)
        XCTAssertNil(layout.bundlePathByItem[gone.id])
    }
}
