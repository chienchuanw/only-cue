import XCTest
@testable import OnlyCue

/// Mirror of `NextCueCountdownTests` for the elapsed-since-last-cue helper.
/// Inclusive `<=` filter is load-bearing: a cue exactly at `currentTime`
/// reads as "Last: 0.0s" rather than nil — the operator just hit the cue
/// and the readout should reflect that.
final class LastCueElapsedTests: XCTestCase {

    func test_lastCueElapsed_noCues_returnsNil() {
        XCTAssertNil(TransportBar.lastCueElapsed(currentTime: 5.0, cues: []))
    }

    func test_lastCueElapsed_allCuesInFuture_returnsNil() {
        let cues = [makeCue(time: 10.0), makeCue(time: 20.0)]
        XCTAssertNil(TransportBar.lastCueElapsed(currentTime: 5.0, cues: cues))
    }

    func test_lastCueElapsed_picksMostRecentPastCue() throws {
        let cues = [makeCue(time: 1.0), makeCue(time: 5.0), makeCue(time: 12.0)]
        let elapsed = try XCTUnwrap(TransportBar.lastCueElapsed(currentTime: 8.0, cues: cues))
        XCTAssertEqual(elapsed, 3.0, accuracy: 0.001)
    }

    func test_lastCueElapsed_currentTimeExactlyOnCue_returnsZero() throws {
        let cues = [makeCue(time: 5.0)]
        let elapsed = try XCTUnwrap(TransportBar.lastCueElapsed(currentTime: 5.0, cues: cues))
        XCTAssertEqual(elapsed, 0.0, accuracy: 0.001)
    }

    func test_lastCueElapsed_unsortedInput_stillPicksMostRecent() throws {
        // Helper shouldn't assume cues are time-sorted; `max()` picks correctly.
        let cues = [makeCue(time: 12.0), makeCue(time: 1.0), makeCue(time: 5.0)]
        let elapsed = try XCTUnwrap(TransportBar.lastCueElapsed(currentTime: 8.0, cues: cues))
        XCTAssertEqual(elapsed, 3.0, accuracy: 0.001)
    }

    private func makeCue(time: TimeInterval) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: 1,
            name: "test",
            time: time,
            notes: "",
            fadeTime: .zero
        )
    }
}
