import XCTest
@testable import OnlyCue

/// #686 — ASCII-only sequence-name sanitizer for grandMA2.
final class MA2NameTests: XCTestCase {
    func test_passesThroughPlainAscii() {
        XCTAssertEqual(MA2Name.sanitize("Opening", fallbackSlot: 5), "Opening")
    }

    func test_dropsNonAscii_andCollapsesWhitespace() {
        XCTAssertEqual(MA2Name.sanitize("開場  Intro", fallbackSlot: 5), "Intro")
        XCTAssertEqual(MA2Name.sanitize("Café  Set", fallbackSlot: 5), "Caf Set")
    }

    func test_stripsDoubleQuotes() {
        XCTAssertEqual(MA2Name.sanitize("a\"b\"c", fallbackSlot: 5), "abc")
    }

    func test_fallsBackWhenEmptyAfterSanitizing() {
        XCTAssertEqual(MA2Name.sanitize("純中文", fallbackSlot: 900), "OnlyCue 900")
        XCTAssertEqual(MA2Name.sanitize("   ", fallbackSlot: 7), "OnlyCue 7")
    }
}
