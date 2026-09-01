import XCTest
@testable import OnlyCue

final class LTCExtentLabelTests: XCTestCase {

    func test_bothBounds_rendersARange() {
        XCTAssertEqual(
            LTCExtentLabel.text(validFrom: 2.0, validUntil: 291.1),
            "00:00:02.0 – 00:04:51.1"
        )
    }

    func test_noBounds_rendersNothing() {
        // Phase 2 has not run, or the document predates #793. Showing
        // "unknown – unknown" would be worse than showing nothing.
        XCTAssertNil(LTCExtentLabel.text(validFrom: nil, validUntil: nil))
    }

    func test_startOnly_rendersAnOpenEndedRange() {
        // Phase 1 has landed but Phase 2 has not.
        XCTAssertEqual(LTCExtentLabel.text(validFrom: 2.0, validUntil: nil), "from 00:00:02.0")
    }

    func test_endOnly_rendersAnOpenStartedRange() {
        XCTAssertEqual(LTCExtentLabel.text(validFrom: nil, validUntil: 61.5), "to 00:01:01.5")
    }

    func test_hoursAreRendered() {
        XCTAssertEqual(LTCExtentLabel.text(validFrom: 3_661.25, validUntil: nil),
                       "from 01:01:01.2")
    }
}
