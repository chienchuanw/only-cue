import XCTest

/// Regression coverage for the right-click context menu on cue rows
/// (issue #291). The first iteration of #291 attached `.contextMenu` as
/// a list-row modifier *after* `.tag` and `.listRowBackground` — SwiftUI's
/// macOS `List` silently dropped the right-click event and the menu never
/// appeared. The fix moves `.contextMenu` *before* those modifiers, the
/// `ItemListPane` / `MediaEditSheet` pattern that's proven to fire reliably.
///
/// This test would fail against the original wiring — right-click yielded
/// no menu items at all. The follow-up "menu item → sheet" hop relies on
/// XCUI's `menuItem.click()` synthesis, which is flaky for SwiftUI's macOS
/// contextMenu Button actions (works in the real app, hit-and-miss in the
/// test harness). The two reliable signals we assert here:
///
///   1. The menu surfaces after a right-click (the regression check).
///   2. The expected menu identifiers are present (catches accidental
///      renames or omissions).
final class CueRowContextMenuUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
    }

    func test_rightClickCueRow_revealsExpectedMenuItems() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let row = try firstCueRow(in: window)
        row.click()
        Thread.sleep(forTimeInterval: 0.3)
        row.rightClick()

        let notes = app.menuItems["cueRowContextEditNotes"]
        let tempo = app.menuItems["cueRowContextTempo"]
        let changeType = app.menuItems["cueRowContextChangeType"]

        XCTAssertTrue(notes.waitForExistence(timeout: 3), "Right-click must reveal 'Edit Notes…'.")
        XCTAssertTrue(tempo.exists, "Right-click must reveal 'Tempo…'.")
        XCTAssertTrue(changeType.exists, "Right-click must reveal 'Change Type ▸'.")

        // Dismiss so the menu state doesn't leak into the next test.
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Helpers

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
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

    private func firstCueRow(in window: XCUIElement) throws -> XCUIElement {
        let row = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Seeded document should display at least one cue row.")
        return row
    }
}
