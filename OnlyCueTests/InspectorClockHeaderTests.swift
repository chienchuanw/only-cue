import XCTest
@testable import OnlyCue

@MainActor
final class InspectorClockHeaderTests: XCTestCase {

    func testFormatsCurrentTimeAsHMSMillis() {
        let engine = PlayerEngine()
        engine.debugSetCurrentTime(83.45)
        XCTAssertEqual(InspectorClockHeader.formatted(engine), "00:01:23.450")
    }

    func testFormatsZeroWhenIdle() {
        let engine = PlayerEngine()
        XCTAssertEqual(InspectorClockHeader.formatted(engine), "00:00:00.000")
    }
}
