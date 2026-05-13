import XCTest
@testable import OnlyCue

final class CueNumberErrorMessageTests: XCTestCase {

    func test_ok_returnsNil() {
        XCTAssertNil(CueNumberErrorMessage.text(for: .ok))
    }

    func test_invalidFormat_returnsFormatMessage() {
        XCTAssertEqual(CueNumberErrorMessage.text(for: .invalidFormat), CueNumberErrorMessage.invalidFormat)
    }

    func test_duplicate_returnsDuplicateMessage() {
        XCTAssertEqual(CueNumberErrorMessage.text(for: .duplicate), CueNumberErrorMessage.duplicate)
    }

    func test_outOfRange_bothBounds_returnsBetweenMessage() {
        XCTAssertEqual(
            CueNumberErrorMessage.text(for: .outOfRange(lowerExclusive: 1.0, upperExclusive: 2.0)),
            "Must be between 1 and 2."
        )
    }

    func test_outOfRange_onlyLower_returnsGreaterThan() {
        XCTAssertEqual(
            CueNumberErrorMessage.text(for: .outOfRange(lowerExclusive: 1.5, upperExclusive: nil)),
            "Must be greater than 1.5."
        )
    }

    func test_outOfRange_onlyUpper_returnsLessThan() {
        XCTAssertEqual(
            CueNumberErrorMessage.text(for: .outOfRange(lowerExclusive: nil, upperExclusive: 2.0)),
            "Must be less than 2."
        )
    }
}
