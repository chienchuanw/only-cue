import XCTest
@testable import OnlyCue

/// Pins the cue-crossing detection used by the pause-at-each-cue mode.
/// Strict `>` on previousTime / inclusive `<=` on newTime is load-bearing —
/// strict avoids re-pausing on resume from a previously-paused-at cue;
/// inclusive ensures a cue exactly at the new playhead position triggers.
final class PauseAtEachCueTests: XCTestCase {

    func test_forwardCrossingFindsCue() throws {
        let cues = [makeCue(time: 5.0), makeCue(time: 12.0)]
        let crossed = try XCTUnwrap(cues.cueCrossed(movingFrom: 4.0, to: 5.5))
        XCTAssertEqual(crossed.time, 5.0, accuracy: 0.001)
    }

    func test_backwardMotionReturnsNil() {
        let cues = [makeCue(time: 5.0), makeCue(time: 12.0)]
        XCTAssertNil(cues.cueCrossed(movingFrom: 10.0, to: 4.0))
    }

    func test_noCuesReturnsNil() {
        let empty: [Cue] = []
        XCTAssertNil(empty.cueCrossed(movingFrom: 0.0, to: 30.0))
    }

    func test_noCueInRangeReturnsNil() {
        let cues = [makeCue(time: 5.0), makeCue(time: 12.0)]
        XCTAssertNil(cues.cueCrossed(movingFrom: 6.0, to: 11.0))
    }

    func test_strictGreaterOnPreviousTime_resumeDoesNotRePause() {
        // After auto-pause at 5.0s, the user resumes; the next tick reports
        // previousTime == 5.0, newTime > 5.0. The cue at 5.0 must NOT be re-detected.
        let cues = [makeCue(time: 5.0), makeCue(time: 12.0)]
        XCTAssertNil(cues.cueCrossed(movingFrom: 5.0, to: 5.1))
    }

    func test_inclusiveLessThanEqualOnNewTime_cueExactlyAtPlayheadTriggers() throws {
        // Playhead arrives exactly at cue.time — pause should trigger.
        let cues = [makeCue(time: 5.0)]
        let crossed = try XCTUnwrap(cues.cueCrossed(movingFrom: 4.5, to: 5.0))
        XCTAssertEqual(crossed.time, 5.0, accuracy: 0.001)
    }

    func test_multipleCuesInRangeReturnsFirst() throws {
        // Scrub-during-play case — multiple cues land in (prev, current].
        // Helper returns the first match (cues are time-sorted in practice;
        // even if not, `.first` picks deterministically).
        let cues = [makeCue(time: 5.0), makeCue(time: 7.0), makeCue(time: 9.0)]
        let crossed = try XCTUnwrap(cues.cueCrossed(movingFrom: 4.0, to: 10.0))
        XCTAssertEqual(crossed.time, 5.0, accuracy: 0.001)
    }

    func test_zeroTickDoesNotTrigger() {
        // previousTime == newTime is not forward motion; the helper bails.
        let cues = [makeCue(time: 5.0)]
        XCTAssertNil(cues.cueCrossed(movingFrom: 5.0, to: 5.0))
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
