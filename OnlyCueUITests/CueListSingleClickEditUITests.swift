import XCTest

/// #786 — a single click on a cue's text column starts editing and must not
/// move the playhead; the leading colour stripe is what seeks.
///
/// The `setListActI` seed opens with the playhead at zero and its earliest cue,
/// "Lights Up", at 18s — so "did the playhead move?" is legible straight off
/// the transport readout.
final class CueListSingleClickEditUITests: OnlyCueUITestCase {

    /// Given a cue named "Lights Up" and the playhead at zero
    /// When I single-click its Name cell, type a new name and press Return
    /// Then the cue is renamed and the playhead has not moved.
    func test_singleClickOnName_editsWithoutMovingThePlayhead() throws {
        let app = launchApp(seed: .setListActI)
        try waitForCueList(in: app)

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15), "the transport readout must be present")
        let timeBeforeEdit = Self.timecode(of: readout)
        XCTAssertFalse(timeBeforeEdit.isEmpty, "the readout must report a timecode to compare against")

        let name = app.staticTexts["Lights Up"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the seeded cue name must be present")

        // One click — not two. This is the whole point of #786.
        name.click()

        let field = app.textFields.firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: 3),
            "a single click on the Name cell must open its text field"
        )

        app.typeKey("a", modifierFlags: .command)
        app.typeText("Rehearsal\r")

        XCTAssertTrue(
            app.staticTexts["Rehearsal"].waitForExistence(timeout: 5),
            "committing the edit must rename the cue"
        )
        XCTAssertFalse(
            app.staticTexts["Lights Up"].exists,
            "the old name must be gone once the rename commits"
        )

        XCTAssertEqual(
            Self.timecode(of: readout),
            timeBeforeEdit,
            "editing a cue's name must not seek the playhead"
        )
    }

    /// A rename must cost exactly one undo entry. `CueCommands.mutateCues`
    /// registers an undo group unconditionally, and #786 gave the rename two
    /// ways to commit — `onSubmit` and focus loss — either of which could write
    /// again on the way out and leave the user pressing Cmd-Z twice to get their
    /// name back. This is the assertion that says it does not.
    func test_renameThenUndo_revertsInASingleUndo() throws {
        let app = launchApp(seed: .setListActI)
        try waitForCueList(in: app)

        let name = app.staticTexts["Lights Up"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the seeded cue name must be present")

        name.click()
        XCTAssertTrue(
            app.textFields.firstMatch.waitForExistence(timeout: 3),
            "a single click on the Name cell must open its text field"
        )
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Rehearsal\r")
        XCTAssertTrue(
            app.staticTexts["Rehearsal"].waitForExistence(timeout: 5),
            "committing the edit must rename the cue"
        )

        app.typeKey("z", modifierFlags: .command)

        XCTAssertTrue(
            app.staticTexts["Lights Up"].waitForExistence(timeout: 5),
            "one Cmd-Z must restore the original name — a second undo entry means the rename committed twice"
        )
    }

    /// The stripe is the row's handle: it is what still selects and seeks once
    /// the three columns have been given over to text entry.
    func test_singleClickOnColourStripe_seeksToTheCue() throws {
        let app = launchApp(seed: .setListActI)
        try waitForCueList(in: app)

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15), "the transport readout must be present")
        let timeBeforeClick = Self.timecode(of: readout)

        // Cues are time-sorted, so the first stripe belongs to "Lights Up" at
        // 18s. The stripe carries no identifier of its own — the row's
        // `cueRow-<id>` propagates over it — so match on element type plus that
        // inherited identifier. Not on the label: "Go to cue" is localized
        // (zh-Hant "跳至此 Cue"), so a label query fails under any other locale.
        let stripe = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(stripe.waitForExistence(timeout: 10), "the cue-type stripe must be present")

        stripe.click()

        let seeked = NSPredicate(format: "value != %@", timeBeforeClick)
        expectation(for: seeked, evaluatedWith: readout)
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error, "clicking the colour stripe must seek the playhead")
        }
        let timeAfterClick = Self.timecode(of: readout)
        XCTAssertTrue(
            timeAfterClick.contains("18"),
            "the playhead must land on the cue's 18s mark, got \(timeAfterClick)"
        )

        XCTAssertFalse(
            app.textFields.firstMatch.exists,
            "clicking the stripe must not open a text field"
        )
    }

    /// #790 — ⇧ and ⌘ are two gestures, not the one "extend" flag #786 read them
    /// as. A ⇧-click on a stripe must select the contiguous run from the anchor.
    ///
    /// Given the playhead parked on "Lights Up" by a plain click on its stripe
    /// When I ⇧-click the third row's stripe
    /// Then the playhead stays put and three cues are selected, not two.
    ///
    /// A multi-row selection has no direct XCUITest observable: it paints a row
    /// background (not queryable) and the `.isSelected` trait is spent on the
    /// playhead's current cue, not on selection. Nor is the ⌫ path available —
    /// `List.onDeleteCommand` needs the list first-responder, and clicking a
    /// stripe (a `Button`) does not give it focus; measured, not assumed. So the
    /// two signals here are the ones the app does publish:
    ///
    /// 1. the playhead — a ⇧-click is `extendRange`, which never seeks, whereas
    ///    a ⇧ that failed to reach `NSEvent.modifierFlags` would fall through to
    ///    the stripe's plain `selectAndSeek` and jump to 165s;
    /// 2. "Renumber Selected…", which appears only for `selection.count >= 2`
    ///    and whose sheet titles itself with the count. Under #786's toggle that
    ///    count would read 2.
    func test_shiftClickOnColourStripe_selectsTheRangeFromTheAnchor() throws {
        let app = launchApp(seed: .setListActI)
        try waitForCueList(in: app)

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15), "the transport readout must be present")

        // The stripes inherit `cueRow-<id>`; cues are time-sorted, so index 0 is
        // "Lights Up" (18s) and index 2 is "Chorus Hit" (165s).
        let stripes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
        XCTAssertTrue(
            stripes.element(boundBy: 2).waitForExistence(timeout: 15),
            "the Set List seed must display at least three cue rows"
        )

        // The plain click sets the anchor — and seeks, which is how we know the
        // click landed on the stripe at all.
        stripes.element(boundBy: 0).click()
        let seeked = NSPredicate(format: "value CONTAINS '18'")
        expectation(for: seeked, evaluatedWith: readout)
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error, "the anchoring click must seek to the first cue's 18s mark")
        }
        let timeAtAnchor = Self.timecode(of: readout)

        // `performWithKeyModifiers` pushes ⇧ as global state, which is what the
        // row's `NSEvent.modifierFlags` read sees.
        XCUIElement.perform(withKeyModifiers: .shift) {
            stripes.element(boundBy: 2).click()
        }

        XCTAssertEqual(
            Self.timecode(of: readout),
            timeAtAnchor,
            "a ⇧-click extends the selection and must not seek — a jump to 165s means ⇧ was dropped"
        )

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
        try openContextMenu(
            on: rows.element(boundBy: 0),
            probe: app.menuItems["cueRowContextEditNotes"],
            describedAs: "cue row context menu"
        )
        let renumber = app.menuItems["cueRowContextRenumberSelected"]
        XCTAssertTrue(
            renumber.waitForExistence(timeout: 3),
            "'Renumber Selected…' is gated on two or more selected cues — one row means the range never happened"
        )
        renumber.click()

        // The sheet titles itself "Renumber N Cues", which is localized — read
        // the digits out rather than matching the English string.
        let sheet = app.descendants(matching: .any).matching(identifier: "renumberCuesSheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "'Renumber Selected…' must open the renumber sheet")
        let selectedCount = (sheet.value as? String ?? "").filter(\.isNumber)
        XCTAssertEqual(
            selectedCount,
            "3",
            "⇧-clicking the third row must select all three rows from the anchor, not just the two clicked"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    /// `setListActI` titles its window "Set List — Act I" rather than the
    /// `seed-` prefix `waitForSeedWindow` matches, so wait on the pane instead.
    private func waitForCueList(in app: XCUIApplication) throws {
        let pane = app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15), "the Set List seed must mount the cue list pane")
    }

    /// A SwiftUI `Text` publishes its string as the AX *value*, not the label —
    /// reading `.label` here returns "" for every playhead position, which
    /// makes an "unchanged" assertion pass without testing anything.
    private static func timecode(of readout: XCUIElement) -> String {
        readout.value as? String ?? ""
    }
}
