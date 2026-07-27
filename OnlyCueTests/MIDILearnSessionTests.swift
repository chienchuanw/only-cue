import XCTest
@testable import OnlyCue

@MainActor
final class MIDILearnSessionTests: XCTestCase {
    func test_capture_bindsFirstMessageToTarget_thenEnds() {
        let session = MIDILearnSession()
        var learned: (MIDIControlID, MIDIAction)?
        session.onLearned = { learned = ($0, $1) }
        session.begin(.discrete(.playPause))
        XCTAssertTrue(session.isActive)
        session.capture(.controlChange(channel: 1, number: 45, value: 127))
        XCTAssertEqual(learned?.0, MIDIControlID(channel: 1, kind: .cc, number: 45))
        XCTAssertEqual(learned?.1, .discrete(.playPause))
        XCTAssertFalse(session.isActive)
    }

    func test_capture_whenInactive_doesNothing() {
        let session = MIDILearnSession()
        var called = false
        session.onLearned = { _, _ in called = true }
        session.capture(.note(channel: 1, number: 60, velocity: 100))
        XCTAssertFalse(called)
    }

    func test_cancel_endsWithoutLearning() {
        let session = MIDILearnSession()
        var called = false
        session.onLearned = { _, _ in called = true }
        session.begin(.continuous(.scrub))
        session.cancel()
        XCTAssertFalse(session.isActive)
        session.capture(.controlChange(channel: 1, number: 45, value: 127))
        XCTAssertFalse(called)
    }
}
