import XCTest
@testable import OnlyCue

/// #592 — cue creation must be blocked in Show mode (read-only) by every entry
/// point (keyboard add-cue, digit add-cue-of-type, OSC /cue/add). They all
/// consult this one pure predicate.
final class CueCreationGateTests: XCTestCase {

    func test_allows_inCueMode_withActiveItem() {
        XCTAssertTrue(CueCreationGate.allows(editorMode: .cue, hasActiveItem: true))
    }

    func test_allows_inLyricMode_withActiveItem() {
        XCTAssertTrue(CueCreationGate.allows(editorMode: .lyric, hasActiveItem: true))
    }

    func test_blocked_inShowMode_evenWithActiveItem() {
        XCTAssertFalse(CueCreationGate.allows(editorMode: .show, hasActiveItem: true))
    }

    func test_blocked_whenNoActiveItem() {
        XCTAssertFalse(CueCreationGate.allows(editorMode: .cue, hasActiveItem: false))
        XCTAssertFalse(CueCreationGate.allows(editorMode: .lyric, hasActiveItem: false))
        XCTAssertFalse(CueCreationGate.allows(editorMode: .show, hasActiveItem: false))
    }
}
