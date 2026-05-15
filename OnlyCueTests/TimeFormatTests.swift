import XCTest
@testable import OnlyCue

final class TimeFormatSMPTETests: XCTestCase {

    func test_smpte_zero_isAllZeros() {
        XCTAssertEqual(TimeFormat.smpte(0, rate: .fps30), "00:00:00:00")
    }

    func test_smpte_oneFrameAt30_isFrame01() {
        XCTAssertEqual(TimeFormat.smpte(1.0 / 30.0, rate: .fps30), "00:00:00:01")
    }

    func test_smpte_halfSecondAt24_is12Frames() {
        XCTAssertEqual(TimeFormat.smpte(3661.5, rate: .fps24), "01:01:01:12")
    }

    func test_smpte_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.smpte(-5, rate: .fps30), "00:00:00:00")
    }

    func test_smpte_dropFrame_usesSemicolonSeparator() {
        let formatted = TimeFormat.smpte(60.0, rate: .fps30drop)
        XCTAssertTrue(
            formatted.contains(";"),
            "drop-frame should use ';' between SS and FF, got \(formatted)"
        )
        XCTAssertFalse(formatted.range(of: #"\d{2};\d{2}$"#, options: .regularExpression) == nil)
    }

    func test_smpte_matchesTimecodeDisplayString() {
        let samples: [(TimeInterval, SMPTEFramerate)] = [
            (0, .fps30), (1.234, .fps30), (3600, .fps24), (75.5, .fps25), (61.0, .fps30drop)
        ]
        for (seconds, rate) in samples {
            let expected = Timecode(totalSeconds: seconds, rate: rate).displayString
            XCTAssertEqual(
                TimeFormat.smpte(seconds, rate: rate),
                expected,
                "smpte(\(seconds), \(rate)) should equal Timecode.displayString"
            )
        }
    }
}

final class TimeFormatSMPTECountdownTests: XCTestCase {

    func test_smpteCountdown_zero_atSubMinute_isSSColonFF() {
        XCTAssertEqual(TimeFormat.smpteCountdown(0, rate: .fps30), "00:00")
    }

    func test_smpteCountdown_subMinute_at30() {
        // 5.5s @ 30fps = 5 sec 15 frames
        XCTAssertEqual(TimeFormat.smpteCountdown(5.5, rate: .fps30), "05:15")
        // 59.9s @ 30fps = 59 sec 27 frames
        XCTAssertEqual(TimeFormat.smpteCountdown(59.9, rate: .fps30), "59:27")
    }

    func test_smpteCountdown_subHour_includesMinute() {
        // 75.5s @ 30fps = 1:15:15
        XCTAssertEqual(TimeFormat.smpteCountdown(75.5, rate: .fps30), "1:15:15")
        // exactly 1 minute @ 24fps = 1:00:00
        XCTAssertEqual(TimeFormat.smpteCountdown(60.0, rate: .fps24), "1:00:00")
    }

    func test_smpteCountdown_hourPlus_includesHour() {
        // 3725.4s @ 30fps = 1:02:05:12
        XCTAssertEqual(TimeFormat.smpteCountdown(3725.4, rate: .fps30), "1:02:05:12")
    }

    func test_smpteCountdown_negative_clampsToZero() {
        XCTAssertEqual(TimeFormat.smpteCountdown(-5, rate: .fps30), "00:00")
    }

    func test_smpteCountdown_dropFrame_usesSemicolonBeforeFrames() {
        let sub = TimeFormat.smpteCountdown(5.0, rate: .fps30drop)
        XCTAssertTrue(sub.contains(";"), "expected ';' separator in \(sub)")
        let hour = TimeFormat.smpteCountdown(3725.0, rate: .fps30drop)
        XCTAssertTrue(hour.contains(";"), "expected ';' separator in \(hour)")
    }
}
