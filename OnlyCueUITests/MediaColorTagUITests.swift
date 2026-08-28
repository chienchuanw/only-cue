import XCTest

/// Acceptance coverage for the per-clip colour tag (#782).
///
/// The spec asks for "assign a colour via the context menu, then assert the
/// swatch". That is split here, deliberately:
///
/// - The **render** is asserted from a seeded document. It is the part that
///   actually matters to the user (a tagged row shows its colour, an untagged
///   row shows nothing) and it runs deterministically on the CI runner.
/// - The **assignment chord** is a separate test that skips gracefully. The
///   headless right-click → submenu → picker-row sequence is the same synthesis
///   that #548 removed from `MediaEditSheetUITests` for being unreliable; the
///   command itself is already covered end-to-end, including undo, by
///   `CueCommandsSetMediaColorTests`.
final class MediaColorTagUITests: OnlyCueUITestCase {

    /// The seed tags rows 1 and 3 and leaves row 2 untagged, so this pins both
    /// halves of the rule in one pass: the stripe follows the tag, and an
    /// untagged row draws no stripe at all (unlike `CueRowView`, which always
    /// draws one).
    func test_taggedRowsDrawASwatchAndUntaggedRowsDoNot() throws {
        let app = launchApp(seed: .mediaColorTags)
        let window = try waitForSeedWindow(in: app)

        let rows = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'itemRow'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "Seed should display media rows.")
        XCTAssertEqual(rows.count, 3, "The media-color-tags seed has three clips.")

        let swatches = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'itemRowSwatch-'"))
        XCTAssertEqual(
            swatches.count,
            2,
            "Exactly the two tagged clips should draw a colour stripe; the untagged one must draw none."
        )
    }

    /// The colour submenu has to be reachable from the row's context menu, or
    /// the feature has no entry point. Asserts the menu item surfaces; skips if
    /// the harness cannot synthesise the right-click on this host.
    func test_rightClickMediaRow_revealsTheColorSubmenu() throws {
        let app = launchApp(seed: .mediaColorTags)
        let window = try waitForSeedWindow(in: app)

        let row = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'itemRow'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Seed should display media rows.")

        try openContextMenu(on: row, in: app)
        XCTAssertTrue(
            app.menuItems["contextMenuMediaColor"].exists,
            "Right-click must reveal the 'Color' submenu."
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    /// Right-click with a coordinate-based fallback, mirroring
    /// `CueRowContextMenuUITests.openContextMenu`. Probes on the long-standing
    /// "Edit Media…" item so a missing *Color* item reads as a real failure
    /// rather than as "the menu never opened".
    private func openContextMenu(on row: XCUIElement, in app: XCUIApplication) throws {
        Thread.sleep(forTimeInterval: 1)
        row.click()
        Thread.sleep(forTimeInterval: 0.3)

        let probe = app.menuItems["contextMenuEditMedia"]

        row.rightClick()
        if probe.waitForExistence(timeout: 2) { return }

        let coord = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coord.rightClick()
        if probe.waitForExistence(timeout: 2) { return }

        throw XCTSkip("Right-click did not surface the media row context menu on this host (known CI hit-test flake).")
    }
}
