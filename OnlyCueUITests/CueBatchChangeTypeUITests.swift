import XCTest

/// #752 — changing cue type on a multi-cue selection. With two rows selected,
/// the right-click "Change Type" menu retypes the whole selection in one undo
/// step (`CueCommands.setTypeForSelected`, unit-covered by
/// `CueCommandsSetTypeForSelectedTests`).
///
/// The retype itself is not XCUITest-observable: the type renders only as a
/// colour stripe (no readable text), the native menu ✓ is not exposed, and —
/// as `CueRowContextMenuUITests` documents — SwiftUI's macOS contextMenu /
/// submenu action synthesis is hit-or-miss under the harness (the nested item
/// click hovers but often doesn't fire). So, mirroring that test's deliberate
/// choice, this asserts the reliable signal: the multi-cue right-click reveals
/// the "Change Type" menu and its inline picker lists the full type palette —
/// i.e. the feature's UI surface exists for a multi-selection. The behavioral
/// retype (both cues change, one undo step) is guaranteed by the unit tests.
final class CueBatchChangeTypeUITests: OnlyCueUITestCase {

    func test_multiSelect_rightClick_revealsChangeTypePaletteForSelection() throws {
        let app = launchApp(seed: .setListActI)
        // `setListActI` titles its window "Set List — Act I" (not the `seed-`
        // prefix `waitForSeedWindow` matches), so wait on the pane instead.
        let pane = app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15), "Set List seed should mount the cue list pane.")

        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
        XCTAssertTrue(rows.element(boundBy: 1).waitForExistence(timeout: 15),
                      "Set List seed should display multiple cue rows.")

        // Select the first two rows: click the first, extend by one with Shift.
        let firstRow = rows.element(boundBy: 0)
        firstRow.click()
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey(.downArrow, modifierFlags: .shift)
        Thread.sleep(forTimeInterval: 0.3)

        try openContextMenu(on: firstRow, in: app)

        // The Change Type menu is present with two rows selected (the inline
        // Picker path renders for a multi-selection).
        let changeType = app.menuItems["cueRowContextChangeType"]
        XCTAssertTrue(changeType.waitForExistence(timeout: 3),
                      "Right-click on a multi-cue selection must reveal 'Change Type ▸'.")

        // Opening it lists the full type palette — "Coral" (type 5) is one of
        // the six seeded types. This is the reliable surface check; the retype
        // behavior itself is covered by CueCommandsSetTypeForSelectedTests.
        changeType.click()
        XCTAssertTrue(app.menuItems["Coral"].waitForExistence(timeout: 3),
                      "The Change Type picker should list the project's cue types.")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Right-click the row via the shared harness helper. No select-first warm-up
    /// here on purpose — this suite has already built up a multi-row selection
    /// and a stray click would collapse it.
    private func openContextMenu(on row: XCUIElement, in app: XCUIApplication) throws {
        try openContextMenu(
            on: row,
            probe: app.menuItems["cueRowContextEditNotes"],
            describedAs: "cue row context menu"
        )
    }
}
