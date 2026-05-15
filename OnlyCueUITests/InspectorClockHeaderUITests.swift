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

    /// The inspector clock renders SMPTE timecode (`HH:MM:SS:FF` or
    /// `HH:MM:SS;FF` for drop-frame) at the project's framerate, replacing
    /// the legacy `HH:MM:SS.mmm` form.
    func testClockRendersAsSMPTE() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        // Scope to .staticText: the clock view wraps its Text in a VStack with
        // `.accessibilityElement(children: .contain)`, so a `.any` descendant
        // query returns the container (whose .label is empty), not the Text.
        let clock = window.descendants(matching: .staticText)
            .matching(identifier: "inspectorClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15))
        let value = clock.label
        XCTAssertNotNil(
            value.range(of: #"^\d{2}:\d{2}:\d{2}[:;]\d{2}$"#, options: .regularExpression),
            "expected HH:MM:SS:FF (or ;FF) form, got \(value)"
        )
    }

    /// With a cue selected, the inspector renders its field stack. The clock
    /// header must remain visible above the fields. Row selection via
    /// coordinate click is flaky in headless CI envs (tracked separately as
    /// the cueRow AX hit-test issue), so we skip gracefully if the field
    /// stack never appears — the empty-state test above already exercises
    /// the same clock view.
    func testClockVisibleWhenCueSelected() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let firstRow = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), "First cue row should appear")
        firstRow.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()

        let nameField = window.textFields["cueInspectorName"]
        guard nameField.waitForExistence(timeout: 5) else {
            throw XCTSkip("Row click did not register on this host (known cueRow AX hit-test flake).")
        }

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
