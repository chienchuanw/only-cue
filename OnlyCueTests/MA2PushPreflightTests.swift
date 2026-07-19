import XCTest
@testable import OnlyCue

/// #683 — before pushing to grandMA2, every filtered cue must carry a unique,
/// non-nil `cueNumber`: OnlyCue and MA2 numbers must match so called cues agree
/// across both. The pre-flight names the offending cues instead of renumbering.
final class MA2PushPreflightTests: XCTestCase {

    private func cue(number: Double?, name: String = "", time: TimeInterval = 0) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: number,
            name: name,
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    func test_allNumberedAndUnique_passes() {
        let cues = [cue(number: 1), cue(number: 1.5), cue(number: 2)]
        XCTAssertTrue(MA2PushPreflight.validate(cues).isEmpty)
    }

    func test_unnumberedCues_reported() {
        let bad1 = cue(number: nil, name: "Intro")
        let bad2 = cue(number: nil, name: "Chorus")
        let issues = MA2PushPreflight.validate([cue(number: 1), bad1, bad2])
        XCTAssertEqual(issues, [.unnumbered(cues: [bad1, bad2])])
    }

    func test_duplicateNumbers_reportedPerNumber() {
        let dupA1 = cue(number: 3, name: "A")
        let dupA2 = cue(number: 3, name: "B")
        let issues = MA2PushPreflight.validate([cue(number: 1), dupA1, dupA2])
        XCTAssertEqual(issues, [.duplicateNumber(number: 3, cues: [dupA1, dupA2])])
    }

    func test_emptyCueList_isReported() {
        // Pushing zero cues is a user error (wrong filter), not a silent no-op.
        XCTAssertEqual(MA2PushPreflight.validate([]), [.noCues])
    }

    func test_issuesAreOrderedStably() {
        let unnumbered = cue(number: nil, name: "X")
        let dup1 = cue(number: 2, name: "C")
        let dup2 = cue(number: 2, name: "D")
        let issues = MA2PushPreflight.validate([dup1, unnumbered, dup2])
        XCTAssertEqual(issues, [
            .unnumbered(cues: [unnumbered]),
            .duplicateNumber(number: 2, cues: [dup1, dup2])
        ])
    }
}
