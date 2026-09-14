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
        let rejected = [
            "", "  ", "abc", "-1", "1/2/3", "1/", "/2", "1/-1", "-1/1",
            "1 / 2", "1/abc", "abc/1",
            "inf", "infinity", "Inf", "+1", "+1/2", "1/+2"
        ]
        for input in rejected {
            XCTAssertNil(FadeTime.parse(input), "expected parse to reject input \(input.debugDescription)")
        }
    }

    // MARK: - format

    func test_format_symmetric_decimal() {
        XCTAssertEqual(FadeTime(fadeIn: 1.5, fadeOut: 1.5).format(), "1.5")
    }

    func test_format_symmetric_whole_dropsTrailingZero() {
        XCTAssertEqual(FadeTime(fadeIn: 1.0, fadeOut: 1.0).format(), "1")
    }

    func test_format_symmetric_zero() {
        XCTAssertEqual(FadeTime(fadeIn: 0, fadeOut: 0).format(), "0")
    }

    func test_format_split() {
        XCTAssertEqual(FadeTime(fadeIn: 1.0, fadeOut: 2.0).format(), "1/2")
    }

    func test_format_splitDecimal() {
        XCTAssertEqual(FadeTime(fadeIn: 0.5, fadeOut: 1.5).format(), "0.5/1.5")
    }

    func test_parseAndFormat_roundTrip_symmetric() throws {
        let parsed = try XCTUnwrap(FadeTime.parse("1.5"))
        XCTAssertEqual(parsed.format(), "1.5")
        XCTAssertEqual(FadeTime.parse(parsed.format()), parsed)
    }

    func test_parseAndFormat_roundTrip_split() throws {
        let parsed = try XCTUnwrap(FadeTime.parse("1/2"))
        XCTAssertEqual(parsed.format(), "1/2")
        XCTAssertEqual(FadeTime.parse(parsed.format()), parsed)
    }

    // MARK: - cellDisplay (cue-list fade cell — numeric, no unit; #804)
    //
    // Seconds is the column's implicit unit, so the cell shows the bare number
    // in `FadeTime.format()` form (whole values drop the trailing `.0`) and
    // blanks a zero fade so an unset fade reads as absence.

    func test_cellDisplay_zero_isBlank() {
        XCTAssertEqual(FadeTime.zero.cellDisplay, "")
    }

    func test_cellDisplay_wholeSymmetric_dropsTrailingZero() {
        XCTAssertEqual(FadeTime.symmetric(2).cellDisplay, "2")
    }

    func test_cellDisplay_decimalSymmetric_keepsDecimal() {
        XCTAssertEqual(FadeTime.symmetric(1.5).cellDisplay, "1.5")
    }

    func test_cellDisplay_split_showsSlashForm() {
        XCTAssertEqual(FadeTime(fadeIn: 1, fadeOut: 2).cellDisplay, "1/2")
    }

    // MARK: - range (#829)
    //
    // A fade leg is bounded at one hour. Above that the value is not a fade a
    // designer meant to type, and it propagates into the MA2 wire format and
    // the cue-list fade column. Two trust boundaries enforce the bound: `parse`
    // (typed text) rejects, and `init(from:)` (file) clamps.

    func test_maximum_isOneHour() {
        XCTAssertEqual(FadeTime.maximum, 3600)
    }

    func test_clamped_passesThroughInRangeValues() {
        XCTAssertEqual(FadeTime.clamped(0), 0)
        XCTAssertEqual(FadeTime.clamped(1.5), 1.5)
        XCTAssertEqual(FadeTime.clamped(FadeTime.maximum), FadeTime.maximum)
    }

    func test_clamped_pullsAboveMaximumDownToMaximum() {
        XCTAssertEqual(FadeTime.clamped(3600.001), FadeTime.maximum)
        XCTAssertEqual(FadeTime.clamped(7200), FadeTime.maximum)
        XCTAssertEqual(FadeTime.clamped(1e21), FadeTime.maximum)
    }

    func test_clamped_pullsNegativeUpToZero() {
        XCTAssertEqual(FadeTime.clamped(-5), 0)
    }

    // Non-finite defeats min/max clamping, so it drops to zero rather than
    // propagating — the same choice `Cue.init` already makes for `bpm`.
    func test_clamped_coercesNonFiniteToZero() {
        XCTAssertEqual(FadeTime.clamped(.infinity), 0)
        XCTAssertEqual(FadeTime.clamped(-.infinity), 0)
        XCTAssertEqual(FadeTime.clamped(.nan), 0)
    }

    // MARK: - decode clamping (file trust boundary, #829)

    func test_decode_clampsOutOfRangeLegs() throws {
        let json = Data(#"{"fadeIn":7200,"fadeOut":-1}"#.utf8)
        let decoded = try JSONDecoder().decode(FadeTime.self, from: json)
        XCTAssertEqual(decoded, FadeTime(fadeIn: FadeTime.maximum, fadeOut: 0))
    }

    func test_decode_clampsAbsurdMagnitude() throws {
        let json = Data(#"{"fadeIn":1e21,"fadeOut":0}"#.utf8)
        let decoded = try JSONDecoder().decode(FadeTime.self, from: json)
        XCTAssertEqual(decoded.fadeIn, FadeTime.maximum)
    }

    func test_decode_leavesInRangeLegsUntouched() throws {
        let json = Data(#"{"fadeIn":1.5,"fadeOut":2}"#.utf8)
        let decoded = try JSONDecoder().decode(FadeTime.self, from: json)
        XCTAssertEqual(decoded, FadeTime(fadeIn: 1.5, fadeOut: 2))
    }

    // MARK: - parse bound (typed-text trust boundary, #829)

    func test_parse_acceptsMaximum() {
        XCTAssertEqual(FadeTime.parse("3600"), FadeTime.symmetric(FadeTime.maximum))
    }

    func test_parse_rejectsAboveMaximum() {
        for input in ["3601", "3600.001", "1/7200", "7200/1", "1e21"] {
            XCTAssertNil(FadeTime.parse(input), "expected parse to reject \(input.debugDescription)")
        }
    }

    // MARK: - formatNumber totality (#829)
    //
    // `formatNumber` is shared with `cueNumber` rendering, which has no decode
    // clamp, so it must be total for every `Double` rather than relying on its
    // callers to pre-filter.

    func test_formatNumber_int64Boundary_staysWholeForm() {
        // Pins the MA2 telnet golden vector's `1e+17` fade case.
        XCTAssertEqual(FadeTime.formatNumber(1e17), "100000000000000000")
    }

    func test_formatNumber_beyondInt64_fallsBackToDoubleDescription() {
        XCTAssertEqual(FadeTime.formatNumber(1e19), "1e+19")
        XCTAssertEqual(FadeTime.formatNumber(1e21), "1e+21")
        XCTAssertEqual(FadeTime.formatNumber(1.5e20), "1.5e+20")
        XCTAssertEqual(FadeTime.formatNumber(-1e19), "-1e+19")
        XCTAssertEqual(FadeTime.formatNumber(-1e21), "-1e+21")
    }

    func test_formatNumber_nonFinite_doesNotTrap() {
        XCTAssertEqual(FadeTime.formatNumber(.infinity), "inf")
        XCTAssertEqual(FadeTime.formatNumber(-.infinity), "-inf")
        XCTAssertEqual(FadeTime.formatNumber(.nan), "nan")
    }
}
