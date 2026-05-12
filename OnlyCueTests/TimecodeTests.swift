import XCTest
@testable import OnlyCue

/// Coverage for `Timecode` / `SMPTEFramerate` — the timecode-arithmetic
/// foundation under epic #33 (LTC generation). Drop-frame counting is the
/// fiddly part, so it's exercised against known boundary values.
final class TimecodeTests: XCTestCase {

    // MARK: - SMPTEFramerate

    func test_framerate_properties() {
        XCTAssertEqual(SMPTEFramerate.fps24.framesPerSecond, 24)
        XCTAssertEqual(SMPTEFramerate.fps25.framesPerSecond, 25)
        XCTAssertEqual(SMPTEFramerate.fps30.framesPerSecond, 30)
        XCTAssertEqual(SMPTEFramerate.fps30drop.framesPerSecond, 30)
        XCTAssertFalse(SMPTEFramerate.fps30.isDropFrame)
        XCTAssertTrue(SMPTEFramerate.fps30drop.isDropFrame)
        XCTAssertEqual(SMPTEFramerate.allCases.map(\.rawValue), ["24", "25", "30", "30df"])
    }

    func test_framerate_codableRawValues() throws {
        let data = try JSONEncoder().encode(SMPTEFramerate.fps30drop)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"30df\"")
        XCTAssertEqual(try JSONDecoder().decode(SMPTEFramerate.self, from: Data("\"25\"".utf8)), .fps25)
    }

    // MARK: - Non-drop round trips

    func test_nonDrop_componentsToFrameCount_andBack() {
        for rate in [SMPTEFramerate.fps24, .fps25, .fps30] {
            let fps = rate.framesPerSecond
            let tc = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: rate)
            let expected = ((1 * 60 + 2) * 60 + 3) * fps + 4
            XCTAssertEqual(tc?.frameCount, expected, "\(rate)")
            XCTAssertEqual(Timecode(frameCount: expected, rate: rate), tc, "\(rate)")
        }
    }

    func test_frameCountZero_isAllZeros() {
        XCTAssertEqual(Timecode(frameCount: 0, rate: .fps25).displayString, "00:00:00:00")
        XCTAssertEqual(Timecode(frameCount: 0, rate: .fps30drop).displayString, "00:00:00;00")
    }

    func test_negativeFrameCount_clampsToZero() {
        XCTAssertEqual(Timecode(frameCount: -5, rate: .fps24), Timecode(frameCount: 0, rate: .fps24))
    }

    // MARK: - Seconds

    func test_totalSeconds_roundTrip() {
        let tc = Timecode(totalSeconds: 90.0, rate: .fps25)
        XCTAssertEqual(tc.displayString, "00:01:30:00")
        XCTAssertEqual(tc.totalSeconds, 90.0, accuracy: 1e-9)
    }

    func test_seconds_roundsToNearestFrame() {
        // 2.4 frames at 25 fps → frame 2.
        XCTAssertEqual(Timecode(totalSeconds: 2.4 / 25.0, rate: .fps25).frames, 2)
        // 2.6 frames → frame 3.
        XCTAssertEqual(Timecode(totalSeconds: 2.6 / 25.0, rate: .fps25).frames, 3)
    }

    // MARK: - Drop frame

    func test_dropFrame_skipsZeroAndOneAtTopOfMinute() {
        // 00:00:59;29 is the last frame of minute 0; the next actual frame is
        // 00:01:00;02 — numbers ;00 and ;01 of minute 1 don't exist.
        let last = Timecode(hours: 0, minutes: 0, seconds: 59, frames: 29, rate: .fps30drop)
        XCTAssertEqual(last?.frameCount, 1799)
        XCTAssertEqual(Timecode(frameCount: 1800, rate: .fps30drop),
                       Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2, rate: .fps30drop))
        // Those skipped numbers are not constructible.
        XCTAssertNil(Timecode(hours: 0, minutes: 1, seconds: 0, frames: 0, rate: .fps30drop))
        XCTAssertNil(Timecode(hours: 0, minutes: 1, seconds: 0, frames: 1, rate: .fps30drop))
    }

    func test_dropFrame_tenthMinute_isNotSkipped() {
        let beforeTen = Timecode(hours: 0, minutes: 9, seconds: 59, frames: 29, rate: .fps30drop)
        let next = Timecode(frameCount: (beforeTen?.frameCount ?? -1) + 1, rate: .fps30drop)
        XCTAssertEqual(next, Timecode(hours: 0, minutes: 10, seconds: 0, frames: 0, rate: .fps30drop))
        XCTAssertNotNil(Timecode(hours: 0, minutes: 10, seconds: 0, frames: 0, rate: .fps30drop))
        XCTAssertNotNil(Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, rate: .fps30drop))
    }

    func test_dropFrame_oneHour_frameCount() {
        // 1 h at 30 fps DF = 108000 − 2·(60 − 6) = 107892 frames elapsed.
        XCTAssertEqual(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps30drop)?.frameCount, 107892)
        XCTAssertEqual(Timecode(frameCount: 107892, rate: .fps30drop).displayString, "01:00:00;00")
    }

    func test_dropFrame_componentsRoundTripAcrossSeveralMinutes() {
        for minute in [1, 2, 9, 10, 11, 30, 59] {
            let tc = Timecode(hours: 0, minutes: minute, seconds: 12, frames: 7, rate: .fps30drop)
            XCTAssertNotNil(tc, "minute \(minute)")
            if let tc { XCTAssertEqual(Timecode(frameCount: tc.frameCount, rate: .fps30drop), tc, "minute \(minute)") }
        }
    }

    // MARK: - Range validation

    func test_outOfRangeComponents_rejected() {
        XCTAssertNil(Timecode(hours: 0, minutes: 0, seconds: 0, frames: 24, rate: .fps24))
        XCTAssertNil(Timecode(hours: 0, minutes: 0, seconds: 0, frames: 30, rate: .fps25))
        XCTAssertNil(Timecode(hours: 0, minutes: 60, seconds: 0, frames: 0, rate: .fps30))
        XCTAssertNil(Timecode(hours: 24, minutes: 0, seconds: 0, frames: 0, rate: .fps25))
        XCTAssertNil(Timecode(hours: 0, minutes: 0, seconds: -1, frames: 0, rate: .fps25))
        XCTAssertNotNil(Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29, rate: .fps30))
    }

    func test_displayString_format() {
        XCTAssertEqual(Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps25)?.displayString,
                       "01:02:03:04")
        XCTAssertEqual(Timecode(hours: 10, minutes: 20, seconds: 30, frames: 15, rate: .fps30drop)?.displayString,
                       "10:20:30;15")
    }
}
