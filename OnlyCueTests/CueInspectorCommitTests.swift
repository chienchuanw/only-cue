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

    func test_commitCueNumber_validNumber_returnsParsed() {
        let outcome = CueInspectorCommit.commitCueNumber(draft: "1.5", current: 1.0)
        XCTAssertEqual(outcome, .parsed(1.5))
    }

    func test_commitCueNumber_unchanged_returnsNoChange() {
        let outcome = CueInspectorCommit.commitCueNumber(draft: "1.5", current: 1.5)
        XCTAssertEqual(outcome, .noChange)
    }

    func test_commitCueNumber_invalid_returnsRevertToInteger() {
        let outcome = CueInspectorCommit.commitCueNumber(draft: "abc", current: 2.0)
        XCTAssertEqual(outcome, .revert(canonical: "2"))
    }

    func test_commitCueNumber_invalid_returnsRevertToDecimal() {
        let outcome = CueInspectorCommit.commitCueNumber(draft: "abc", current: 1.5)
        XCTAssertEqual(outcome, .revert(canonical: "1.5"))
    }

    func test_commitCueNumber_emptyWithExistingNumber_returnsCleared() {
        let outcome = CueInspectorCommit.commitCueNumber(draft: "  ", current: 3.0)
        XCTAssertEqual(outcome, .cleared)
    }

    func test_commitCueNumber_emptyWhenAlreadyNil_returnsNoChange() {
        let outcome = CueInspectorCommit.commitCueNumber(draft: "", current: nil)
        XCTAssertEqual(outcome, .noChange)
    }

    func test_commitCueNumber_negativeAllowed_returnsParsedAndValidatorDecidesFate() {
        // The pure helper only parses; sign and range checks live in CueNumberValidator.
        let outcome = CueInspectorCommit.commitCueNumber(draft: "-1", current: 0.0)
        XCTAssertEqual(outcome, .parsed(-1.0))
    }

    func test_commitCueNumber_currentIsNilAndDraftIsNumber_returnsParsed() {
        let outcome = CueInspectorCommit.commitCueNumber(draft: "1.5", current: nil)
        XCTAssertEqual(outcome, .parsed(1.5))
    }

    // MARK: - Cue name (#786)
    //
    // With a single click starting an edit and focus loss committing it,
    // deciding *whether* a rename should be written is worth proving without
    // driving the UI.

    func test_commitCueName_unchanged_commitsNothing() {
        XCTAssertNil(CueInspectorCommit.commitCueName(draft: "Verse", current: "Verse"))
    }

    func test_commitCueName_trimsSurroundingWhitespace() {
        XCTAssertEqual(CueInspectorCommit.commitCueName(draft: "  Chorus  ", current: "Verse"), "Chorus")
    }

    func test_commitCueName_whitespaceOnlyEdit_commitsNothing() {
        XCTAssertNil(CueInspectorCommit.commitCueName(draft: "  Verse  ", current: "Verse"))
    }

    /// #661 made an empty cue name render blank rather than "Untitled", so
    /// clearing the field is a legal edit. The pre-#786 `commitRename()`
    /// swallowed it (`guard !trimmed.isEmpty`), which is the behaviour this
    /// test exists to prevent from coming back.
    func test_commitCueName_clearingAName_commitsAnEmptyString() {
        XCTAssertEqual(CueInspectorCommit.commitCueName(draft: "", current: "Verse"), "")
    }

    func test_commitCueName_treatsWhitespaceAsEmpty() {
        XCTAssertEqual(CueInspectorCommit.commitCueName(draft: "   ", current: "Verse"), "")
    }

    func test_commitCueName_clearingAnAlreadyEmptyName_commitsNothing() {
        XCTAssertNil(CueInspectorCommit.commitCueName(draft: "   ", current: ""))
    }
}
