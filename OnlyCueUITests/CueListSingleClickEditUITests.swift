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
        let timeBeforeEdit = readout.label

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
            readout.label,
            timeBeforeEdit,
            "editing a cue's name must not seek the playhead"
        )
    }

    /// The stripe is the row's handle: it is what still selects and seeks once
    /// the three columns have been given over to text entry.
    func test_singleClickOnColourStripe_seeksToTheCue() throws {
        let app = launchApp(seed: .setListActI)
        try waitForCueList(in: app)

        let readout = app.staticTexts["currentTimeReadout"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15), "the transport readout must be present")
        let timeBeforeClick = readout.label

        // Cues are time-sorted, so the first row is "Lights Up" at 18s.
        let stripe = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRowSwatch-'"))
            .firstMatch
        XCTAssertTrue(stripe.waitForExistence(timeout: 10), "the cue-type stripe must be present")

        stripe.click()

        let seeked = NSPredicate(format: "label != %@", timeBeforeClick)
        expectation(for: seeked, evaluatedWith: readout)
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error, "clicking the colour stripe must seek the playhead")
        }
        XCTAssertTrue(
            readout.label.contains("18"),
            "the playhead must land on the cue's 18s mark, got \(readout.label)"
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
}
