import CoreGraphics
import XCTest
@testable import OnlyCue

/// The pure width policy for the resizable Mini Player panel (#761): a single
/// source of truth for the min / max / default width and the clamp used both when
/// configuring the panel and when restoring a persisted (autosave) width.
final class MiniPlayerSizeTests: XCTestCase {

    func test_constants() {
        XCTAssertEqual(MiniPlayerSize.min, 660)
        XCTAssertEqual(MiniPlayerSize.max, 1000)
        XCTAssertEqual(MiniPlayerSize.default, 660)
    }

    func test_clampBelowMin_returnsMin() {
        XCTAssertEqual(MiniPlayerSize.clamp(620), 660)
        XCTAssertEqual(MiniPlayerSize.clamp(0), 660)
        XCTAssertEqual(MiniPlayerSize.clamp(-100), 660)
    }

    func test_clampAboveMax_returnsMax() {
        XCTAssertEqual(MiniPlayerSize.clamp(1200), 1000)
        XCTAssertEqual(MiniPlayerSize.clamp(5000), 1000)
    }

    func test_clampInRange_unchanged() {
        XCTAssertEqual(MiniPlayerSize.clamp(660), 660)
        XCTAssertEqual(MiniPlayerSize.clamp(800), 800)
        XCTAssertEqual(MiniPlayerSize.clamp(1000), 1000)
    }

    func test_clampNonFinite_returnsDefault() {
        XCTAssertEqual(MiniPlayerSize.clamp(.nan), MiniPlayerSize.default)
        XCTAssertEqual(MiniPlayerSize.clamp(.infinity), MiniPlayerSize.default)
    }
}
