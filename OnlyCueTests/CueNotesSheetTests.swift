import XCTest
import SwiftUI
@testable import OnlyCue

@MainActor
final class CueNotesSheetTests: XCTestCase {

    func test_commitForwardsCurrentDraftToOnSave() {
        // The sheet seeds its draft from `initialNotes`, so a test that
        // wants to verify "save commits the user's text" can pass that
        // text as `initialNotes` and call testCommit() directly.
        var captured: String?
        let sheet = CueNotesSheet(
            cueLabel: "Cue 1 · Test",
            initialNotes: "new notes",
            onSave: { captured = $0 },
            onCancel: {}
        )
        sheet.testCommit()
        XCTAssertEqual(captured, "new notes")
    }

    func test_cancelDoesNotInvokeOnSave() {
        var saveCalled = false
        var cancelCalled = false
        let sheet = CueNotesSheet(
            cueLabel: "Cue 1 · Test",
            initialNotes: "old",
            onSave: { _ in saveCalled = true },
            onCancel: { cancelCalled = true }
        )
        sheet.testCancel()
        XCTAssertFalse(saveCalled)
        XCTAssertTrue(cancelCalled)
    }

    func test_initialDraftMatchesInitialNotes() {
        let sheet = CueNotesSheet(
            cueLabel: "Cue 1 · Test",
            initialNotes: "hello",
            onSave: { _ in },
            onCancel: {}
        )
        XCTAssertEqual(sheet.testCurrentDraft, "hello")
    }

    func test_emptyInitialNotes_commitsEmptyString() {
        var captured: String?
        let sheet = CueNotesSheet(
            cueLabel: "Cue 1",
            initialNotes: "",
            onSave: { captured = $0 },
            onCancel: {}
        )
        sheet.testCommit()
        XCTAssertEqual(captured, "")
    }
}
