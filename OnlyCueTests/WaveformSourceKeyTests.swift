import XCTest
@testable import OnlyCue

/// #589 — the waveform resolve task must re-fire when the active item OR its
/// bookmark changes, so a relink (which mutates `bookmarkData` in place on the
/// same item id) refreshes the waveform instead of sticking on the spinner.
final class WaveformSourceKeyTests: XCTestCase {

    func test_differsWhenBookmarkChanges_forSameItem() {
        let id = UUID()
        let before = WaveformSourceKey(itemID: id, bookmark: Data([0x01]))
        let after = WaveformSourceKey(itemID: id, bookmark: Data([0x02]))
        XCTAssertNotEqual(before, after, "A relink changes the bookmark → the resolve task must re-fire")
    }

    func test_equalWhenUnchanged() {
        let id = UUID()
        XCTAssertEqual(
            WaveformSourceKey(itemID: id, bookmark: Data([0x01])),
            WaveformSourceKey(itemID: id, bookmark: Data([0x01]))
        )
    }

    func test_differsWhenItemChanges() {
        XCTAssertNotEqual(
            WaveformSourceKey(itemID: UUID(), bookmark: nil),
            WaveformSourceKey(itemID: UUID(), bookmark: nil)
        )
    }

    func test_noActiveItem_isStable() {
        XCTAssertEqual(
            WaveformSourceKey(itemID: nil, bookmark: nil),
            WaveformSourceKey(itemID: nil, bookmark: nil)
        )
    }
}
