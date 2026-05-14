import XCTest

final class InspectorClockHeaderUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
    }

    /// With a seeded document open and no cue selected, the inspector is in
    /// the empty state. The clock header sits above the "Select a cue"
    /// placeholder and must still be visible.
    func testClockVisibleInEmptyState() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .any)
            .matching(identifier: "inspectorClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 15),
            "inspectorClock should be visible in empty-state inspector"
        )
    }

    /// With a cue selected, the inspector renders its field stack. The clock
    /// header must remain visible above the fields.
    func testClockVisibleWhenCueSelected() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let firstRow = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), "First cue row should appear")
        firstRow.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()

        let nameField = window.textFields["cueInspectorName"]
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 5),
            "Inspector fields should appear once a cue is selected"
        )

        let clock = window.descendants(matching: .any)
            .matching(identifier: "inspectorClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 5),
            "inspectorClock should remain visible when a cue is selected"
        )
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [key.launchArgument]
        app.launch()
        return app
    }

    /// The seed window title is `seed-<UUID>.cuelist`. State-restoration may
    /// reopen older docs alongside it, so scoping all queries to the seeded
    /// window prevents stale-state false negatives.
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
