import XCTest

/// #804 — the cue list's Fade column. Single-clicking a Fade cell opens its
/// editor; committing a new value writes it back and the cell reflects it.
///
/// The `setListActI` seed gives "Lights Up" a 1.5 s fade, so its Fade cell reads
/// "1.5 s" — a value unique across the seed's six cues, so matching on it can
/// never hit the wrong row.
final class CueListFadeColumnUITests: OnlyCueUITestCase {

    /// Given "Lights Up" with a 1.5 s fade
    /// When I single-click its Fade cell, replace the value with "4" and press Return
    /// Then the Fade cell reads "4.0 s".
    func test_editingFadeCell_commitsAndUpdatesTheDisplay() throws {
        let app = launchApp(seed: .setListActI)
        let pane = app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15), "the Set List seed must mount the cue list pane")

        let fadeCell = app.staticTexts["1.5 s"]
        XCTAssertTrue(
            fadeCell.waitForExistence(timeout: 10),
            "the seeded 1.5 s fade must render in the Fade column"
        )

        fadeCell.click()
        let field = app.textFields.firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: 3),
            "a single click on the Fade cell must open its text field"
        )

        app.typeKey("a", modifierFlags: .command)
        app.typeText("4\r")

        XCTAssertTrue(
            app.staticTexts["4.0 s"].waitForExistence(timeout: 5),
            "committing the edit must update the Fade cell to the new value"
        )
        XCTAssertFalse(
            app.staticTexts["1.5 s"].exists,
            "the old fade value must be gone once the edit commits"
        )
    }
}
