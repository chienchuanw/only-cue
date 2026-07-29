import XCTest
@testable import OnlyCue

/// #657 — type-filtered stepping / GO / activeCue for Show mode's GO-by-type.
/// A `nil` typeID = all cues (existing behaviour); a non-nil id considers only
/// cues of that type.
final class MediaItemTypeFilterTests: XCTestCase {

    private let typeA = UUID()
    private let typeB = UUID()

    private func cue(_ time: TimeInterval, _ typeID: UUID) -> Cue {
        Cue(id: UUID(), typeID: typeID, cueNumber: nil, name: "c", time: time, notes: "", fadeTime: .zero)
    }

    private func clip(_ cues: [Cue]) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(displayName: "x.wav", kind: .audio, duration: 100, bookmarkData: Data([1])),
            cues: cues
        )
    }

    /// Cues: A@1, B@2, A@3, B@5.
    private func mixed() -> MediaItem {
        clip([cue(1, typeA), cue(2, typeB), cue(3, typeA), cue(5, typeB)])
    }

    func test_stepNext_type_skipsOtherTypes() {
        // from 1: next A is 3 (skips B@2).
        XCTAssertEqual(mixed().cue(steppingFrom: 1, direction: .next, typeID: typeA)?.time, 3)
    }

    func test_stepNext_nil_walksAll() {
        // regression: nil walks all → next after 1 is 2.
        XCTAssertEqual(mixed().cue(steppingFrom: 1, direction: .next, typeID: nil)?.time, 2)
    }

    func test_stepPrev_type_skipsOtherTypes() {
        // from 6: B candidates are 2 and 5, the active one is 5, so the step
        // lands on 2 — skipping A@3 entirely.
        XCTAssertEqual(mixed().cue(steppingFrom: 6, direction: .previous, typeID: typeB)?.time, 2)
    }

    func test_stepPrev_type_insideFirstMatchingCue_returnsNil() {
        // from 4 the active B is 2 and no B precedes it, so there is nowhere to
        // step back to — even though A@3 sits between them (#709).
        XCTAssertNil(mixed().cue(steppingFrom: 4, direction: .previous, typeID: typeB))
    }

    func test_go_type_seeksNextMatchingType() {
        XCTAssertEqual(mixed().showGoDecision(from: 1, typeID: typeA), .seekAndPlay(3))
    }

    func test_go_type_pastLastMatching_noOp() {
        // last A is 3; from 4 there is no next A.
        XCTAssertEqual(mixed().showGoDecision(from: 4, typeID: typeA), .noOp)
    }

    func test_activeCue_type_latestMatchingAtOrBefore() {
        // at 4: latest B at/before 4 is 2 (A@3 ignored).
        XCTAssertEqual(mixed().activeCue(at: 4, typeID: typeB)?.time, 2)
    }

    func test_activeCue_nil_walksAll() {
        // regression: at 4, latest any at/before 4 is 3.
        XCTAssertEqual(mixed().activeCue(at: 4, typeID: nil)?.time, 3)
    }
}
