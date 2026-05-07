import XCTest
@testable import OnlyCue

final class TimeFormatTests: XCTestCase {

    func test_zero_isAllZeros() {
        XCTAssertEqual(TimeFormat.hms(0), "00:00:00.000")
    }

    func test_subSecond_showsMilliseconds() {
        XCTAssertEqual(TimeFormat.hms(1.5), "00:00:01.500")
        XCTAssertEqual(TimeFormat.hms(0.001), "00:00:00.001")
        XCTAssertEqual(TimeFormat.hms(0.250), "00:00:00.250")
    }

    func test_oneMinute_rollsOverFromSeconds() {
        XCTAssertEqual(TimeFormat.hms(60), "00:01:00.000")
        XCTAssertEqual(TimeFormat.hms(59.999), "00:00:59.999")
    }

    func test_oneHour_rollsOverFromMinutes() {
        XCTAssertEqual(TimeFormat.hms(3600), "01:00:00.000")
        XCTAssertEqual(TimeFormat.hms(3599.999), "00:59:59.999")
    }

    func test_complexCase_roundsAndPadsCorrectly() {
        XCTAssertEqual(TimeFormat.hms(3661.234), "01:01:01.234")
    }

    func test_negativeInput_clampsToZero() {
        XCTAssertEqual(TimeFormat.hms(-5.0), "00:00:00.000")
    }

    func test_subMillisecond_roundsHalfAwayFromZero() {
        XCTAssertEqual(TimeFormat.hms(0.0005), "00:00:00.001")
        XCTAssertEqual(TimeFormat.hms(0.0014), "00:00:00.001")
        XCTAssertEqual(TimeFormat.hms(0.0015), "00:00:00.002")
    }
}
