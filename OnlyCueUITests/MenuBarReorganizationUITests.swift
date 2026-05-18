import XCTest

final class MenuBarReorganizationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_cueMenu_existsWithRenamedCueCommands() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let cueMenu = app.menuBars.menuBarItems["Cue"]
        XCTAssertTrue(cueMenu.waitForExistence(timeout: 5))
        cueMenu.click()

        XCTAssertTrue(app.menuItems["Duplicate at Playhead"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Nudge Back"].exists)
        XCTAssertTrue(app.menuItems["Nudge Forward"].exists)
        XCTAssertTrue(app.menuItems["Snap to Playhead"].exists)
        XCTAssertTrue(app.menuItems["Snap to Nearest Beat"].exists)
        XCTAssertTrue(app.menuItems["Snap to Nearest Bar"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_pauseAtEachCue_isUnderPlaybackMenu() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let playbackMenu = app.menuBars.menuBarItems["Playback"]
        XCTAssertTrue(playbackMenu.waitForExistence(timeout: 5))
        playbackMenu.click()
        XCTAssertTrue(app.menuItems["Pause at Each Cue"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_viewMenu_noLongerContainsCueEditingItems() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let viewBarItem = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewBarItem.waitForExistence(timeout: 5))
        viewBarItem.click()

        // Scope to the open View dropdown — an app-wide menuItems query would
        // also match the Cue/Playback menus, which legitimately host these now.
        let viewMenu = viewBarItem.menus.firstMatch
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 3))
        XCTAssertTrue(viewMenu.menuItems["Zoom In Horizontally"].exists)
        XCTAssertTrue(viewMenu.menuItems["Zoom In Vertically"].exists)
        XCTAssertFalse(viewMenu.menuItems["Zoom In"].exists)
        XCTAssertFalse(viewMenu.menuItems["Snap to Playhead"].exists)
        XCTAssertFalse(viewMenu.menuItems["Snap Selected Cue to Playhead"].exists)
        XCTAssertFalse(viewMenu.menuItems["Pause at Each Cue"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            SeedKey.threeCuesAt1And3And6.launchArgument
        ]
        app.launch()
        return app
    }

    private func waitForSeedWindow(in app: XCUIApplication, timeout: TimeInterval = 15) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = app.windows.allElementsBoundByIndex
            if let match = windows.first(where: { $0.title.hasPrefix("seed-") }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
