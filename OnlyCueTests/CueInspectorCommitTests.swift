import XCTest
@testable import OnlyCue

final class CueInspectorCommitTests: XCTestCase {

    func test_commitFadeTime_validSplit_returnsParsed() {
        let outcome = CueInspectorCommit.commitFadeTime(draft: "1/2", current: .zero)
        XCTAssertEqual(outcome, .parsed(FadeTime(fadeIn: 1.0, fadeOut: 2.0)))
    }

    func test_commitFadeTime_validSymmetric_returnsParsed() {
        let outcome = CueInspectorCommit.commitFadeTime(draft: "1.5", current: .zero)
        XCTAssertEqual(outcome, .parsed(.symmetric(1.5)))
    }

    func test_commitFadeTime_unchanged_returnsNoChange() {
        let outcome = CueInspectorCommit.commitFadeTime(draft: "1.5", current: .symmetric(1.5))
        XCTAssertEqual(outcome, .noChange)
    }

    func test_commitFadeTime_invalid_returnsRevertToCanonical() {
        let outcome = CueInspectorCommit.commitFadeTime(draft: "abc", current: .symmetric(1.5))
        XCTAssertEqual(outcome, .revert(canonical: "1.5"))
    }

    func test_commitFadeTime_invalidWhenSplit_revertsToSplitCanonical() {
        let outcome = CueInspectorCommit.commitFadeTime(
            draft: "abc",
            current: FadeTime(fadeIn: 1.0, fadeOut: 2.0)
        )
        XCTAssertEqual(outcome, .revert(canonical: "1/2"))
    }

    func test_commitFadeTime_empty_returnsRevert() {
        let outcome = CueInspectorCommit.commitFadeTime(draft: "", current: .symmetric(2.0))
        XCTAssertEqual(outcome, .revert(canonical: "2"))
    }
}
