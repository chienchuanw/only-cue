import XCTest

final class PlayheadClockHeaderUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "chienchuanw.OnlyCue") {
            app.forceTerminate()
        }
    }

    /// With a seeded document open, the playhead clock sits at the top of
    /// the cue list pane and is visible.
    func testClockVisibleAtTopOfCueListPane() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 15),
            "playheadClock should be visible above the cue list."
        )
    }

    /// The playhead clock renders SMPTE timecode (`HH:MM:SS:FF` or
    /// `HH:MM:SS;FF` for drop-frame) at the project's framerate.
    func testClockRendersAsSMPTE() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        // Scope to .staticText: the clock view wraps its Text in a VStack with
        // `.accessibilityElement(children: .contain)`, so a `.any` descendant
        // query returns the container (whose .label is empty), not the Text.
        let clock = window.descendants(matching: .staticText)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15))
        let text = clock.label.isEmpty ? (clock.value as? String ?? "") : clock.label
        XCTAssertNotNil(
            text.range(of: #"^\d{2}:\d{2}:\d{2}[:;]\d{2}$"#, options: .regularExpression),
            "expected HH:MM:SS:FF (or ;FF) form, got label='\(clock.label)' value='\(clock.value ?? "nil")'"
        )
    }

    /// Selecting a cue must not hide the clock — it stays pinned at the top.
    func testClockVisibleWhenCueSelected() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let firstRow = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), "First cue row should appear")
        firstRow.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 5),
            "playheadClock should remain visible when a cue is selected."
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
