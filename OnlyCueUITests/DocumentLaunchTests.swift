import XCTest

final class DocumentLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: New document opens
    /// Given the app is launched fresh
    /// When the user creates a new document (⌘N)
    /// Then a window appears
    /// And the no-media onboarding content (Import button + shortcut hints) is visible.
    ///
    /// Note: macOS `DocumentGroup` does not auto-open an untitled document
    /// on cold launch; it shows the launcher / start window. The user
    /// reaches a document window via ⌘N or the "New Document" button. We
    /// drive ⌘N to mirror the Gherkin "When the user creates a new
    /// document".
    func test_newDocument_showsEmptyStateOnboarding() throws {
        let app = XCUIApplication()
        app.launch()

        app.typeKey("n", modifierFlags: .command)

        let importButton = app.buttons["importMediaButton"]
        XCTAssertTrue(
            importButton.waitForExistence(timeout: 5),
            "Import Media button should appear within 5 seconds of ⌘N"
        )
        XCTAssertTrue(
            app.staticTexts["documentShortcutHints"].exists,
            "Shortcut hints should be visible in the no-media state"
        )
    }
}
