import XCTest
@testable import OnlyCue

@MainActor
final class InspectorClockHeaderTests: XCTestCase {

    /// The inspector clock formats its readout via `TimeFormat.smpte` at the
    /// project framerate seeded into the environment. The static helper went
    /// away when the view switched to an `@Environment` framerate, so these
    /// tests assert the underlying formatter contract the view uses.
    func testFormatsCurrentTimeAsSMPTE() {
        // 83.45s @ 30fps = 1 min, 23 sec, 14 frames (.45s * 30 = 13.5 → 14)
        XCTAssertEqual(TimeFormat.smpte(83.45, rate: .fps30), "00:01:23:14")
    }

    func testFormatsZeroAsSMPTE() {
        XCTAssertEqual(TimeFormat.smpte(0, rate: .fps30), "00:00:00:00")
    }
}
