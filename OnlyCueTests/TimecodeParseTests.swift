import XCTest
@testable import OnlyCue

/// Coverage for `Timecode.parse(_:rate:)` — the `HH:MM:SS:FF` text → `Timecode`
/// parser used by the Timecode Settings sheet (epic #33 leaf 6, timecode half).
final class TimecodeParseTests: XCTestCase {

    func test_parsesColonForm() throws {
        XCTAssertEqual(
            Timecode.parse("01:02:03:04", rate: .fps25),
            Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps25)
        )
    }

    func test_parsesSemicolonFormForDropFrame_separatorIsPunctuationOnly() throws {
        XCTAssertEqual(
            Timecode.parse("01:02:03;04", rate: .fps30drop),
            Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps30drop)
        )
        // The `;` doesn't make a 30-fps (non-drop) parse drop-frame — `rate` decides.
        XCTAssertEqual(Timecode.parse("00:00:01;05", rate: .fps30)?.rate, .fps30)
    }

    func test_toleratesWhitespaceAndMixedSeparators() throws {
        XCTAssertEqual(
            Timecode.parse("  01 : 02 : 03 . 04 ", rate: .fps24),
            Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps24)
        )
    }

    func test_rejectsWrongFieldCount() {
        XCTAssertNil(Timecode.parse("01:02:03", rate: .fps25))
        XCTAssertNil(Timecode.parse("01:02:03:04:05", rate: .fps25))
        XCTAssertNil(Timecode.parse("", rate: .fps25))
        XCTAssertNil(Timecode.parse("01020304", rate: .fps25))
    }

    func test_rejectsNonIntegerFields() {
        XCTAssertNil(Timecode.parse("01:02:0x:04", rate: .fps25))
        XCTAssertNil(Timecode.parse("a:b:c:d", rate: .fps25))
    }

    func test_rejectsOutOfRangeComponents() {
        XCTAssertNil(Timecode.parse("01:02:03:30", rate: .fps25))   // frame ≥ fps
        XCTAssertNil(Timecode.parse("01:60:03:04", rate: .fps30))   // minute ≥ 60
        XCTAssertNil(Timecode.parse("24:00:00:00", rate: .fps25))   // hour ≥ 24
        XCTAssertNotNil(Timecode.parse("23:59:59:23", rate: .fps24))
    }

    func test_dropFrame_rejectsSkippedFrameNumbers_butAcceptsTenthMinute() {
        XCTAssertNil(Timecode.parse("01:01:00;00", rate: .fps30drop))   // minute 1 of hour 1 → skipped
        XCTAssertNil(Timecode.parse("00:01:00;01", rate: .fps30drop))   // skipped
        XCTAssertNotNil(Timecode.parse("00:01:00;02", rate: .fps30drop))
        XCTAssertNotNil(Timecode.parse("00:10:00;00", rate: .fps30drop)) // tenth minute → not skipped
        XCTAssertNotNil(Timecode.parse("00:00:00;00", rate: .fps30drop))
    }

    func test_roundTripsThroughDisplayString() throws {
        let original = try XCTUnwrap(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25))
        XCTAssertEqual(Timecode.parse(original.displayString, rate: .fps25), original)
        let dropFrame = try XCTUnwrap(Timecode(hours: 0, minutes: 10, seconds: 30, frames: 15, rate: .fps30drop))
        XCTAssertEqual(Timecode.parse(dropFrame.displayString, rate: .fps30drop), dropFrame)
    }
}
