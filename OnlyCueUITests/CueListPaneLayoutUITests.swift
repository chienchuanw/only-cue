import XCTest

/// Layout regression for issue #293 — the Cue Inspector pane is gone,
/// the playhead clock is pinned above the cue list, and nothing in the
/// window claims the old `cueInspector` identifier.
final class CueListPaneLayoutUITests: OnlyCueUITestCase {

    func test_playheadClockIsPresent() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(
            clock.waitForExistence(timeout: 15),
            "playheadClock must exist above the cue list."
        )
    }

    func test_noInspectorContainer() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let pane = window.descendants(matching: .any)
            .matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15), "cueListPane should be present")

        let inspector = window.descendants(matching: .any)
            .matching(identifier: "cueInspector").firstMatch
        XCTAssertFalse(
            inspector.exists,
            "cueInspector container must not exist after #293 — the inspector pane was removed."
        )
        XCTAssertFalse(
            window.textFields["cueInspectorName"].exists,
            "cueInspectorName field must not exist."
        )
        XCTAssertFalse(
            window.textFields["cueInspectorNumber"].exists,
            "cueInspectorNumber field must not exist."
        )
        XCTAssertFalse(
            window.textFields["cueInspectorFade"].exists,
            "cueInspectorFade field must not exist."
        )
    }

    func test_clockSitsAboveCueList() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let clock = window.descendants(matching: .any)
            .matching(identifier: "playheadClock").firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 15))

        let firstRow = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15), "First cue row should appear")

        // Clock's bottom edge must sit at or above the row's top edge.
        // Small tolerance for sub-pixel rendering and divider spacing.
        let tolerance: CGFloat = 2
        XCTAssertLessThanOrEqual(
            clock.frame.maxY,
            firstRow.frame.minY + tolerance,
            "Clock (maxY=\(clock.frame.maxY)) should render above row (minY=\(firstRow.frame.minY))."
        )
    }

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        launchApp(seed: key)
    }
}
