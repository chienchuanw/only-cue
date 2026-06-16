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

    func test_autoScrollWaveform_isInViewMenu_andClickable() throws {
        // The Auto-Scroll Waveform item (#532) is a checkmark toggle, but the
        // checkmark state is NOT exposed to XCUITest (neither `value` nor
        // `isSelected` reflects it for a SwiftUI menu item), so this smoke-checks
        // the menu wiring — the item is present and a click round-trips without
        // error. The flip + auto-follow gating are unit-tested in
        // `WaveformZoomControllerTests`.
        let app = launchSeeded()
        _ = try waitForSeedWindow(in: app)

        let viewBarItem = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewBarItem.waitForExistence(timeout: 5))
        viewBarItem.click()

        let item = viewBarItem.menus.firstMatch.menuItems["Auto-Scroll Waveform"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "View menu exposes the Auto-Scroll Waveform toggle")
        XCTAssertTrue(item.isHittable, "the toggle is clickable")
        item.click() // toggles the persisted preference

        // Reopen and click again to restore the original state (so the toggle
        // doesn't leak across runs) and confirm the item survives a round-trip.
        viewBarItem.click()
        let item2 = viewBarItem.menus.firstMatch.menuItems["Auto-Scroll Waveform"]
        XCTAssertTrue(item2.waitForExistence(timeout: 3), "the toggle remains in the menu after clicking")
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
