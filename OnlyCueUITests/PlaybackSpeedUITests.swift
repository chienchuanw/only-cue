import XCTest

final class PlaybackSpeedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_playbackMenu_hasSpeedItems() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)
        let playbackMenu = app.menuBars.menuBarItems["Playback"]
        XCTAssertTrue(playbackMenu.waitForExistence(timeout: 5))
        playbackMenu.click()
        XCTAssertTrue(app.menuItems["Speed Up"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Slow Down"].exists)
        XCTAssertTrue(app.menuItems["Reset Speed"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_speedUpMenuItem_showsBadgeWithIncreasedRate() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        for _ in 0..<3 {
            clickPlaybackItem(in: app, title: "Speed Up")
        }

        let badge = app.buttons["playbackRateBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 3))
        XCTAssertEqual(badge.label, "1.3×")

        clickPlaybackItem(in: app, title: "Reset Speed")
        XCTAssertTrue(badge.waitForNonExistence(timeout: 4))
    }

    // Popover content (slider + reset button) isn't reliably reachable through
    // macOS XCUI accessibility — SwiftUI's popover doesn't always surface its
    // children. The popover is exercised by manual verification; the menu items
    // and badge update are covered by the two tests above.

    private func clickPlaybackItem(in app: XCUIApplication, title: String) {
        let playbackMenu = app.menuBars.menuBarItems["Playback"]
        XCTAssertTrue(playbackMenu.waitForExistence(timeout: 3))
        playbackMenu.click()
        let item = app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 2))
        item.click()
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
