import XCTest

/// #804 — the cue list's Fade column. Single-clicking a Fade cell opens its
/// editor; committing a new value writes it back and the cell reflects it.
///
/// The `setListActI` seed gives "Lights Up" a 1.5 s fade, so its Fade cell reads
/// "1.5" (seconds is the column's implicit unit — no " s") — a value unique
/// across the seed's six cues, so matching on it can never hit the wrong row.
final class CueListFadeColumnUITests: OnlyCueUITestCase {

    /// Given "Lights Up" with a 1.5 s fade shown as "1.5"
    /// When I single-click its Fade cell, replace the value with "2.5" and press Return
    /// Then the Fade cell reads "2.5".
    ///
    /// The new value is a decimal (not a whole number) on purpose: a whole
    /// number like "4" also appears as a cue *number* in the seed, so a decimal
    /// keeps the assertion unambiguous.
    func test_editingFadeCell_commitsAndUpdatesTheDisplay() throws {
        let app = launchApp(seed: .setListActI)
        let pane = app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15), "the Set List seed must mount the cue list pane")

        let fadeCell = app.staticTexts["1.5"]
        XCTAssertTrue(
            fadeCell.waitForExistence(timeout: 10),
            "the seeded 1.5 s fade must render as \"1.5\" in the Fade column"
        )

        fadeCell.click()
        let field = app.textFields.firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: 3),
            "a single click on the Fade cell must open its text field"
        )

        app.typeKey("a", modifierFlags: .command)
        app.typeText("2.5\r")

        XCTAssertTrue(
            app.staticTexts["2.5"].waitForExistence(timeout: 5),
            "committing the edit must update the Fade cell to the new value"
        )
        XCTAssertFalse(
            app.staticTexts["1.5"].exists,
            "the old fade value must be gone once the edit commits"
        )
    }
}
