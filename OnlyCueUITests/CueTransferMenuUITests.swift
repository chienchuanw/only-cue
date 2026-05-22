import XCTest

/// Given OnlyCue is running, When the user opens the Cue menu, Then it offers
/// Export Cue List… and Import Cue List….
final class CueTransferMenuUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func test_cueMenu_offersExportAndImportCueList() {
        let app = XCUIApplication()
        app.launch()

        let cueMenu = app.menuBars.menuBarItems["Cue"]
        XCTAssertTrue(cueMenu.waitForExistence(timeout: 10), "Cue menu should exist")
        cueMenu.click()

        XCTAssertTrue(
            app.menuItems["Export Cue List…"].waitForExistence(timeout: 5),
            "Cue menu should contain Export Cue List…"
        )
        XCTAssertTrue(
            app.menuItems["Import Cue List…"].exists,
            "Cue menu should contain Import Cue List…"
        )
    }
}
