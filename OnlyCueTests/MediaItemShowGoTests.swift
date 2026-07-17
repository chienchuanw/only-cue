import XCTest
@testable import OnlyCue

/// #645 — Show-mode GO decision. `showGoDecision(from:)` picks the next cue
/// strictly after the playhead (reusing `cue(steppingFrom:.next)`): a hit means
/// "seek there and play"; no next cue means no-op.
final class MediaItemShowGoTests: XCTestCase {

    private func cue(_ time: TimeInterval) -> Cue {
        Cue(id: UUID(), typeID: UUID(), cueNumber: nil, name: "c", time: time, notes: "", fadeTime: .zero)
    }

    private func clip(cues: [Cue]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "x.wav", kind: .audio, duration: 100, bookmarkData: Data([1])),
            cues: cues
        )
    }

    func test_go_seeksAndPlaysNextCueAfterPlayhead() {
        XCTAssertEqual(clip(cues: [cue(5), cue(10), cue(20)]).showGoDecision(from: 7), .seekAndPlay(10))
    }

    func test_go_beforeFirstCue_seeksFirst() {
        XCTAssertEqual(clip(cues: [cue(5), cue(10)]).showGoDecision(from: 0), .seekAndPlay(5))
    }

    func test_go_pastLastCue_noOp() {
        XCTAssertEqual(clip(cues: [cue(5), cue(10)]).showGoDecision(from: 12), .noOp)
    }

    func test_go_emptyCues_noOp() {
        XCTAssertEqual(clip(cues: []).showGoDecision(from: 0), .noOp)
    }

    func test_go_cueExactlyAtPlayhead_isSkipped() {
        // Strict on the playhead: the cue at 5 is skipped, next is 10.
        XCTAssertEqual(clip(cues: [cue(5), cue(10)]).showGoDecision(from: 5), .seekAndPlay(10))
    }
}
