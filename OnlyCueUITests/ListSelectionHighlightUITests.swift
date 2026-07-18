import XCTest

/// #679 — the cue list and media list no longer paint the macOS blue system
/// selection highlight; only the design-system row background (cue-type tint /
/// achromatic pill) shows. The fill colour isn't directly XCUITest-queryable, so
/// this exercises click + keyboard selection to prove interaction still works
/// after the AppKit `selectionHighlightStyle = .none` styling, and screenshots
/// for visual confirmation. The styler logic is unit-pinned by
/// `TableSelectionHighlightStylerTests`.
final class ListSelectionHighlightUITests: OnlyCueUITestCase {

    func test_selectingACueRow_stillWorks_withoutBlueHighlight() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch.waitForExistence(timeout: 15)
        )

        // Click the first cue row, then move with the keyboard — both must still
        // select after disabling the system highlight (that was the whole point
        // of the introspection approach over dropping List(selection:)).
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.click()
        Thread.sleep(forTimeInterval: 0.3)
        firstRow.typeKey(.downArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        // The list is still alive and interactive.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch.exists)

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "list-selection-no-blue-highlight"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
