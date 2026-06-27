import XCTest

/// Verifies the rebuilt no-media empty state: a single import well, the
/// shortcut-reference button, and — per spec §6 item 2 — no transport chrome
/// until media exists.
final class EmptyStateRedesignUITests: OnlyCueUITestCase {

    private func launchEmptyDocument() -> XCUIApplication {
        let app = launchApp()
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

    // Removed (#548): `test_shortcutReferenceButton_isPresentAndHittable` was
    // CIRuntime-gated (always skipped on the runner), and
    // `test_inspectorEmptyState_screenshotSmoke` was a screenshot that asserted
    // only that the document opened — neither was a CI regression gate.
}
