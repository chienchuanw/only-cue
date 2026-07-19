import XCTest
@testable import OnlyCue

/// #683 Approach A — a cue's absolute timecode encoded for `Assign … /TrigTime=`.
/// Value is decimal seconds on the project frame grid; the console quantizes to
/// its slot's timecode format.
final class MA2TrigTimeTests: XCTestCase {

    func test_seconds_snapsToFrameGrid_withStartOffset() {
        // 30 fps, start at frame 90 (=3.0 s), cue at 2.1333 s → +64 frames → frame 154.
        let seconds = MA2TrigTime.seconds(cueTime: 2.1333, startTimecodeFrames: 90, framerate: .fps30)
        XCTAssertEqual(seconds, 154.0 / 30.0, accuracy: 1e-9)
    }

    func test_command_trimsTrailingZeros_forWholeSeconds() {
        // 150 frames / 30 fps = 5.0 s → "5".
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0, startTimecodeFrames: 150, framerate: .fps30), "5")
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0, startTimecodeFrames: 0, framerate: .fps25), "0")
    }

    func test_command_keepsFractionalSeconds() {
        // 64 frames / 30 fps = 2.13333… → trimmed 6-dp string.
        XCTAssertEqual(MA2TrigTime.command(cueTime: 0, startTimecodeFrames: 64, framerate: .fps30), "2.133333")
    }

    func test_fps30drop_usesNominalThirty() {
        let seconds = MA2TrigTime.seconds(cueTime: 1.0, startTimecodeFrames: 0, framerate: .fps30drop)
        XCTAssertEqual(seconds, 30.0 / 30.0, accuracy: 1e-9)
    }
}
