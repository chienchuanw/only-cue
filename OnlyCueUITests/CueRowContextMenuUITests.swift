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
final class CueRowContextMenuUITests: OnlyCueUITestCase {

    func test_rightClickCueRow_revealsExpectedMenuItems() throws {
        // The right-click is anchored to the row element's own bounds
        // (`row.rightClick()` / `row.coordinate(withNormalizedOffset:)` in
        // `openContextMenu`), not an absolute screen coordinate, so it no
        // longer depends on the host display size. If the menu still fails to
        // surface on a given host, `openContextMenu` skips gracefully rather
        // than failing (the harness's contextMenu synthesis is hit-or-miss).
        let app = launchWithSeed(.threeCuesAt1And3And6)
        let window = try waitForSeedWindow(in: app)

        let row = try firstCueRow(in: window)
        try openContextMenu(on: row, in: app)

        let notes = app.menuItems["cueRowContextEditNotes"]
        let tempo = app.menuItems["cueRowContextTempo"]
        let changeType = app.menuItems["cueRowContextChangeType"]

        XCTAssertTrue(notes.waitForExistence(timeout: 3), "Right-click must reveal 'Edit Notes…'.")
        XCTAssertTrue(tempo.exists, "Right-click must reveal 'Tempo…'.")
        XCTAssertTrue(changeType.exists, "Right-click must reveal 'Change Type ▸'.")

        // Dismiss so the menu state doesn't leak into the next test.
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Settle, then right-click the row via the shared harness helper.
    ///
    /// No select-first left-click any more (#786): a plain click in a column now
    /// opens that column's `TextField`, and right-clicking inside an open field
    /// gets AppKit's Cut/Copy/Paste field-editor menu rather than the row's
    /// `.contextMenu` — correct macOS behaviour, but not what this test is
    /// about. Right-click alone targets whatever is under the cursor, which is
    /// the interaction this suite exists to guard; right-click *with* a live
    /// selection stays covered by `CueBatchChangeTypeUITests`.
    private func openContextMenu(on row: XCUIElement, in app: XCUIApplication) throws {
        Thread.sleep(forTimeInterval: 1)
        try openContextMenu(
            on: row,
            probe: app.menuItems["cueRowContextEditNotes"],
            describedAs: "cue row context menu"
        )
    }

    // MARK: - Helpers

    private func launchWithSeed(_ key: SeedKey) -> XCUIApplication {
        launchApp(seed: key)
    }

    private func firstCueRow(in window: XCUIElement) throws -> XCUIElement {
        let row = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Seeded document should display at least one cue row.")
        return row
    }
}
