import XCTest
@testable import OnlyCue

/// Pins the pure command→seek-target mapping `OSCServerHost` uses to dispatch
/// `/stop`, `/skip`, and `/locate`. The clamps to >= 0 are the load-bearing
/// part — a `/skip -100` from the playhead at 10s must land at 0, not -90.
final class OSCServerHostTests: XCTestCase {

    func test_stop_seeksToZero_regardlessOfCurrentTime() {
        XCTAssertEqual(OSCServerHost.resolvedSeekTime(for: .stop, currentTime: 0), 0)
        XCTAssertEqual(OSCServerHost.resolvedSeekTime(for: .stop, currentTime: 123.4), 0)
    }

    func test_skipForward_addsToCurrentTime() {
        XCTAssertEqual(OSCServerHost.resolvedSeekTime(for: .skip(seconds: 5), currentTime: 10), 15)
    }

    func test_skipBackward_clampsToZero() {
        XCTAssertEqual(OSCServerHost.resolvedSeekTime(for: .skip(seconds: -100), currentTime: 10), 0)
    }

    func test_skipBackward_withinBounds_subtracts() {
        XCTAssertEqual(OSCServerHost.resolvedSeekTime(for: .skip(seconds: -3), currentTime: 10), 7)
    }

    func test_locate_positivePassesThrough() {
        XCTAssertEqual(OSCServerHost.resolvedSeekTime(for: .locate(seconds: 30), currentTime: 50), 30)
    }

    func test_locate_negativeClampsToZero() {
        XCTAssertEqual(OSCServerHost.resolvedSeekTime(for: .locate(seconds: -3), currentTime: 50), 0)
    }

    func test_nonSeekCommands_returnNil() {
        XCTAssertNil(OSCServerHost.resolvedSeekTime(for: .play, currentTime: 0))
        XCTAssertNil(OSCServerHost.resolvedSeekTime(for: .pause, currentTime: 0))
        XCTAssertNil(OSCServerHost.resolvedSeekTime(for: .cueAdd, currentTime: 0))
        XCTAssertNil(OSCServerHost.resolvedSeekTime(for: .cueNext, currentTime: 0))
        XCTAssertNil(OSCServerHost.resolvedSeekTime(for: .cuePrev, currentTime: 0))
    }
}
