import XCTest
@testable import OnlyCue

/// #765 — the per-song executor text field parses `"page.number"` and treats blank/malformed
/// input as unassigned (#764).
final class MA2ExecutorFieldTests: XCTestCase {

    func test_parsesPageDotNumber() {
        let executor = MA2ExecutorField.parse("2.7")
        XCTAssertEqual(executor?.page, 2)
        XCTAssertEqual(executor?.number, 7)
    }

    func test_blankOrWhitespace_isUnassigned() {
        XCTAssertNil(MA2ExecutorField.parse(""))
        XCTAssertNil(MA2ExecutorField.parse("   "))
    }

    func test_malformedOrNonPositive_isUnassigned() {
        XCTAssertNil(MA2ExecutorField.parse("1"))
        XCTAssertNil(MA2ExecutorField.parse("1.2.3"))
        XCTAssertNil(MA2ExecutorField.parse("a.b"))
        XCTAssertNil(MA2ExecutorField.parse("0.1"))
        XCTAssertNil(MA2ExecutorField.parse("1.0"))
    }

    func test_text_roundTrips() {
        XCTAssertEqual(MA2ExecutorField.text(page: 1, number: 3), "1.3")
        XCTAssertEqual(MA2ExecutorField.text(page: nil, number: nil), "")
    }
}
