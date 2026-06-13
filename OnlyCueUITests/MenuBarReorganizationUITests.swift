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

    func test_viewMenuToggles_useShowHideVerb_andFlipOnClick() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let viewBarItem = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewBarItem.waitForExistence(timeout: 5))
        viewBarItem.click()

        let viewMenu = viewBarItem.menus.firstMatch
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 3))

        // Don't assume the initial state: these flags are @AppStorage-backed,
        // so they persist across runs (and are shared with the developer's
        // real app usage locally). Each toggle must simply offer exactly one
        // of its Show/Hide verbs — never both, never neither.
        for label in ["Notes Overlay", "Timeline Breakdown", "Tempo Grid"] {
            let show = viewMenu.menuItems["Show \(label)"].exists
            let hide = viewMenu.menuItems["Hide \(label)"].exists
            XCTAssertTrue(show != hide, "'\(label)' must offer exactly one verb (show=\(show) hide=\(hide)).")
        }

        // Flip Tempo Grid from whatever state it's in; the verb must invert.
        // ("Show" present => currently hidden; clicking it shows the grid.)
        let startedHidden = viewMenu.menuItems["Show Tempo Grid"].exists
        let clickedVerb = startedHidden ? "Show Tempo Grid" : "Hide Tempo Grid"
        let flippedVerb = startedHidden ? "Hide Tempo Grid" : "Show Tempo Grid"
        viewMenu.menuItems[clickedVerb].click()

        viewBarItem.click()
        let viewMenu2 = viewBarItem.menus.firstMatch
        XCTAssertTrue(viewMenu2.waitForExistence(timeout: 3))
        XCTAssertTrue(viewMenu2.menuItems[flippedVerb].exists, "Tempo Grid verb must flip to '\(flippedVerb)'.")
        XCTAssertFalse(viewMenu2.menuItems[clickedVerb].exists)

        // Restore the original state so this toggle doesn't leak into later
        // tests / runs — the leakage that made this test brittle (#378).
        viewMenu2.menuItems[flippedVerb].click()
        app.typeKey(.escape, modifierFlags: [])
    }

    func test_autoScrollWaveform_isACheckmarkToggleInViewMenu_andFlipsOnClick() throws {
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let viewBarItem = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewBarItem.waitForExistence(timeout: 5))
        viewBarItem.click()

        let viewMenu = viewBarItem.menus.firstMatch
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 3))

        // A single stable-label checkmark item (#532), not a Show/Hide verb-flip.
        let item = viewMenu.menuItems["Auto-Scroll Waveform"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        // Don't assume initial state — @AppStorage persists across runs. The
        // checkmark surfaces as the NSMenuItem state (value "1" = on).
        let startedOn = (item.value as? String) == "1"
        item.click()

        viewBarItem.click()
        let viewMenu2 = viewBarItem.menus.firstMatch
        XCTAssertTrue(viewMenu2.waitForExistence(timeout: 3))
        let item2 = viewMenu2.menuItems["Auto-Scroll Waveform"]
        XCTAssertTrue(item2.waitForExistence(timeout: 3))
        let nowOn = (item2.value as? String) == "1"
        XCTAssertNotEqual(startedOn, nowOn, "Clicking must flip the checkmark state.")

        // Restore so the toggle doesn't leak into later tests / runs.
        item2.click()
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
