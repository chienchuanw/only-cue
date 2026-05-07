import XCTest

final class DocumentLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: New document opens
    /// Given the app is launched fresh
    /// When the user creates a new document (⌘N)
    /// Then a window appears
    /// And the placeholder content (title + cue count) is visible.
    ///
    /// Note: macOS `DocumentGroup` does not auto-open an untitled document
    /// on cold launch; it shows the launcher / start window. The user
    /// reaches a document window via ⌘N or the "New Document" button. We
    /// drive ⌘N to mirror the Gherkin "When the user creates a new
    /// document".
    func test_newDocument_showsPlaceholderContent() throws {
        let app = XCUIApplication()
        app.launch()

        app.typeKey("n", modifierFlags: .command)

        let documentTitle = app.staticTexts["documentTitle"]
        XCTAssertTrue(
            documentTitle.waitForExistence(timeout: 5),
            "documentTitle should appear within 5 seconds of ⌘N"
        )
        XCTAssertEqual(
            documentTitle.label,
            "OnlyCue",
            "documentTitle should display the app name"
        )

        let cueCount = app.staticTexts["cueCount"]
        XCTAssertTrue(
            cueCount.exists,
            "cueCount label should be visible alongside the title"
        )
        XCTAssertEqual(
            cueCount.label,
            "0 cues",
            "Empty document should report 0 cues"
        )
    }
}
