import XCTest
@testable import OnlyCue

/// #786 — with a single click starting an edit and focus loss committing it,
/// deciding *whether* a rename should be written is worth pulling out of the
/// view so it can be proved without driving the UI.
final class CueRowNameCommitTests: XCTestCase {

    func test_unchangedName_commitsNothing() {
        XCTAssertNil(CueRowNameCommit.value(draft: "Verse", current: "Verse"))
    }

    func test_surroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(CueRowNameCommit.value(draft: "  Chorus  ", current: "Verse"), "Chorus")
    }

    func test_whitespaceOnlyEdit_commitsNothing() {
        XCTAssertNil(CueRowNameCommit.value(draft: "  Verse  ", current: "Verse"))
    }

    /// #661 made an empty cue name render blank rather than "Untitled", so
    /// clearing the field is a legal edit. The pre-#786 `commitRename()`
    /// swallowed it (`guard !trimmed.isEmpty`), which is the behaviour this
    /// test exists to prevent from coming back.
    func test_clearingAName_commitsAnEmptyString() {
        XCTAssertEqual(CueRowNameCommit.value(draft: "", current: "Verse"), "")
    }

    func test_clearingAName_treatsWhitespaceAsEmpty() {
        XCTAssertEqual(CueRowNameCommit.value(draft: "   ", current: "Verse"), "")
    }

    func test_clearingAnAlreadyEmptyName_commitsNothing() {
        XCTAssertNil(CueRowNameCommit.value(draft: "   ", current: ""))
    }
}
