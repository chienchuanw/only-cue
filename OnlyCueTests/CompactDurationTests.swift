import XCTest
@testable import OnlyCue

final class CompactDurationTests: XCTestCase {

    /// Sub-hour clip lengths render `M:SS` (Figma sidebar `318:1238`).
    func test_subHour_rendersMinutesSeconds() {
        XCTAssertEqual(TimeFormat.compactDuration(222), "3:42")
        XCTAssertEqual(TimeFormat.compactDuration(59), "0:59")
        XCTAssertEqual(TimeFormat.compactDuration(60), "1:00")
        XCTAssertEqual(TimeFormat.compactDuration(0), "0:00")
    }

    /// Hour-plus lengths add the hour field as `H:MM:SS`.
    func test_hourPlus_rendersHoursMinutesSeconds() {
        XCTAssertEqual(TimeFormat.compactDuration(3600), "1:00:00")
        XCTAssertEqual(TimeFormat.compactDuration(3700), "1:01:40")
        XCTAssertEqual(TimeFormat.compactDuration(7384), "2:03:04")
    }

    /// The fractional second is truncated (a clip in its Nth second reads N).
    func test_fractionalSecond_truncates() {
        XCTAssertEqual(TimeFormat.compactDuration(222.9), "3:42")
    }

    /// Negative input clamps to zero.
    func test_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.compactDuration(-5), "0:00")
    }
}
