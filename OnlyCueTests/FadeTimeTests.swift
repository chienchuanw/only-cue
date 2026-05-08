import XCTest
@testable import OnlyCue

final class FadeTimeTests: XCTestCase {

    func test_symmetric_codableRoundTrip() throws {
        let original = FadeTime(fadeIn: 1.5, fadeOut: 1.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FadeTime.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_split_codableRoundTrip_preservesIndependentInAndOut() throws {
        let original = FadeTime(fadeIn: 1.0, fadeOut: 2.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FadeTime.self, from: data)
        XCTAssertEqual(decoded.fadeIn, 1.0)
        XCTAssertEqual(decoded.fadeOut, 2.0)
    }

    // MARK: - parse

    func test_parse_acceptsInteger_returnsSymmetric() {
        XCTAssertEqual(FadeTime.parse("1"), FadeTime(fadeIn: 1, fadeOut: 1))
    }

    func test_parse_acceptsDecimal_returnsSymmetric() {
        XCTAssertEqual(FadeTime.parse("1.5"), FadeTime(fadeIn: 1.5, fadeOut: 1.5))
    }

    func test_parse_acceptsZero_returnsSymmetric() {
        XCTAssertEqual(FadeTime.parse("0"), FadeTime(fadeIn: 0, fadeOut: 0))
    }

    func test_parse_acceptsSplit_returnsAsymmetric() {
        XCTAssertEqual(FadeTime.parse("1/2"), FadeTime(fadeIn: 1.0, fadeOut: 2.0))
    }

    func test_parse_acceptsSplitDecimal() {
        XCTAssertEqual(FadeTime.parse("0.5/1.0"), FadeTime(fadeIn: 0.5, fadeOut: 1.0))
    }

    func test_parse_trimsSurroundingWhitespace() {
        XCTAssertEqual(FadeTime.parse("  1.5  "), FadeTime(fadeIn: 1.5, fadeOut: 1.5))
    }

    func test_parse_rejectsMalformedInputs() {
        let rejected = ["", "  ", "abc", "-1", "1/2/3", "1/", "/2", "1/-1", "-1/1", "1 / 2", "1/abc", "abc/1"]
        for input in rejected {
            XCTAssertNil(FadeTime.parse(input), "expected parse to reject input \(input.debugDescription)")
        }
    }
}
