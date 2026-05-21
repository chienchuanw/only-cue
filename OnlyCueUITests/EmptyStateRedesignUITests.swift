import XCTest

/// Verifies the rebuilt no-media empty state: a single import well, the
/// shortcut-reference button, and — per spec §6 item 2 — no transport chrome
/// until media exists.
final class EmptyStateRedesignUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchEmptyDocument() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        return app
    }

    func test_emptyState_showsImportWell_andHidesTransport() throws {
        let app = launchEmptyDocument()
        XCTAssertTrue(
            app.buttons["importMediaButton"].waitForExistence(timeout: 15),
            "the empty state should offer the Import Media button"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["documentImportWell"].exists,
            "the import well should be present in the no-media state"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["transportControls"].exists,
            "the transport must be hidden until media exists (spec §6 item 2)"
        )
    }

    func test_shortcutReferenceButton_isPresentAndHittable() throws {
        let app = launchEmptyDocument()
        let help = app.buttons["shortcutReferenceButton"]
        XCTAssertTrue(
            help.waitForExistence(timeout: 15),
            "the shortcut-reference button should appear in the empty state"
        )
        XCTAssertTrue(help.isHittable, "the shortcut-reference button should be clickable")
        help.click()
    }

    /// The cue-list inspector's empty-state copy must be present in full — it
    /// was clipped before the Quiet Pro redesign (spec §6 item 4). The icon +
    /// text VStack merges into one AX element, so the full sentence is asserted
    /// as a substring of the merged `cueListEmptyState` label.
    func test_inspectorEmptyState_messageIsPresentAndUntruncated() throws {
        let app = launchEmptyDocument()
        let emptyState = app.descendants(matching: .any)["cueListEmptyState"]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 15),
            "the cue-list empty state should be present"
        )
        XCTAssertTrue(
            emptyState.label.contains("Import a media file to start adding cues."),
            "the empty-state copy should be the full, untruncated sentence — got: '\(emptyState.label)'"
        )
    }
}
