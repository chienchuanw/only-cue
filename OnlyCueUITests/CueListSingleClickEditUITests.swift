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

    /// Focus-loss commit (#786) means Return can fire `commitRename` twice: once
    /// from `onSubmit`, then again when tearing down the `TextField` drops
    /// focus. `CueCommands.mutateCues` registers an undo group unconditionally,
    /// so a second write would cost the user a second Cmd-Z to get their name
    /// back. One Cmd-Z must be enough.
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
