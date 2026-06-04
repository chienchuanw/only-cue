import XCTest
@testable import OnlyCue

final class LyricsTimeFormatTests: XCTestCase {

    // MARK: - parse

    func test_parse_bareSeconds() {
        XCTAssertEqual(LyricsTimeFormat.parse("9"), 9)
    }

    func test_parse_minutesSeconds() {
        XCTAssertEqual(LyricsTimeFormat.parse("1:30"), 90)
    }

    func test_parse_hoursMinutesSeconds() {
        XCTAssertEqual(LyricsTimeFormat.parse("1:02:03"), 3723)
    }

    func test_parse_fractionalSeconds() throws {
        XCTAssertEqual(try XCTUnwrap(LyricsTimeFormat.parse("0:02.250")), 2.25, accuracy: 0.0001)
    }

    func test_parse_trimsWhitespace() {
        XCTAssertEqual(LyricsTimeFormat.parse("  1:00  "), 60)
    }

    func test_parse_rejectsGarbage() {
        XCTAssertNil(LyricsTimeFormat.parse("abc"))
        XCTAssertNil(LyricsTimeFormat.parse(""))
        XCTAssertNil(LyricsTimeFormat.parse("1:2:3:4"))
        XCTAssertNil(LyricsTimeFormat.parse("-5"))
        XCTAssertNil(LyricsTimeFormat.parse("1:99"))
    }

    // MARK: - string

    func test_string_subMinute() {
        XCTAssertEqual(LyricsTimeFormat.string(2.25), "0:02.250")
    }

    func test_string_minutes() {
        XCTAssertEqual(LyricsTimeFormat.string(90), "1:30.000")
    }

    func test_string_hours() {
        XCTAssertEqual(LyricsTimeFormat.string(3723), "1:02:03.000")
    }

    func test_string_roundTripsWithParse() throws {
        let value = LyricsTimeFormat.parse(LyricsTimeFormat.string(137.5))
        XCTAssertEqual(try XCTUnwrap(value), 137.5, accuracy: 0.0001)
    }

    func test_string_nearIntegerSecond_carriesIntoSecondsField() {
        // A near-integer time must not produce a malformed ".1000" fraction —
        // it carries into the seconds (and minutes) field instead.
        XCTAssertEqual(LyricsTimeFormat.string(59.9996), "1:00.000")
        XCTAssertEqual(LyricsTimeFormat.string(2.9999), "0:03.000")
        XCTAssertEqual(LyricsTimeFormat.string(3599.9999), "1:00:00.000")
    }

    // MARK: - clockString (placed-lyric inspector rows, #463 / Figma 318:1369)

    func test_clockString_zeroPaddedHoursMinutesSeconds_oneDecimalTenths() {
        // Figma placed rows: 00:00:06.3 / 00:00:51.6 / 00:02:12.0 / 00:02:55.0
        XCTAssertEqual(LyricsTimeFormat.clockString(6.3), "00:00:06.3")
        XCTAssertEqual(LyricsTimeFormat.clockString(51.6), "00:00:51.6")
        XCTAssertEqual(LyricsTimeFormat.clockString(132.0), "00:02:12.0")
        XCTAssertEqual(LyricsTimeFormat.clockString(175.0), "00:02:55.0")
    }

    func test_clockString_pastAnHour_keepsTwoDigitFields() {
        XCTAssertEqual(LyricsTimeFormat.clockString(3661.5), "01:01:01.5")
    }

    func test_clockString_negativeClampsToZero() {
        XCTAssertEqual(LyricsTimeFormat.clockString(-5), "00:00:00.0")
    }

    func test_clockString_roundsToNearestTenth_carryingUp() {
        XCTAssertEqual(LyricsTimeFormat.clockString(59.96), "00:01:00.0")
    }
}
