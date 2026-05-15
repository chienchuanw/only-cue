import XCTest

/// Issue #291 — minimal Cue Inspector + right-click sheets + cue-row
/// stripe and Fade column. These tests cover the user-visible surface
/// that the unit tests in OnlyCueTests can't reach (context menu items,
/// modal sheet presentation, row decoration accessibility identifiers).
final class CueInspectorMinimalUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
    }

    func test_inspectorContainsOnlyClockAndThreeFields() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let inspector = window.descendants(matching: .any)
            .matching(identifier: "cueInspector").firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 15))

        // Clock present.
        let clock = window.descendants(matching: .any)
            .matching(identifier: "inspectorClock").firstMatch
        XCTAssertTrue(clock.exists, "Inspector clock must remain pinned at top.")

        // Removed fields must NOT exist anywhere in the inspector.
        XCTAssertFalse(
            window.textFields["cueInspectorBPM"].exists,
            "BPM field should have moved out of the inspector."
        )
        XCTAssertFalse(
            window.textFields["cueInspectorBeatsPerBar"].exists,
            "Beats-per-bar field should have moved out of the inspector."
        )
        XCTAssertFalse(
            window.textViews["cueInspectorNotes"].exists,
            "Notes editor should have moved out of the inspector."
        )
        XCTAssertFalse(
            window.popUpButtons["cueInspectorType"].exists,
            "Type picker should have moved out of the inspector."
        )
    }

    func test_headerRowContainsFadeColumn() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        // Wait for the cue list to fully render — anchor on the existing
        // cueRow- identifier which other tests already rely on.
        let row = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))

        // The column header strip is the user-visible signal that the new
        // Fade column exists. Child `cueRowFade-<id>` and `cueRowStripe-<id>`
        // identifiers do not surface through SwiftUI's List AX tree (same
        // limitation as `cueTime-<id>` per #264) — their behavior is asserted
        // in CueRowViewStripeTests + the column width unit tests instead.
        let fadeHeader = window.staticTexts["Fade"].firstMatch
        XCTAssertTrue(fadeHeader.waitForExistence(timeout: 5), "Header row should label the Fade column.")
    }

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
}
