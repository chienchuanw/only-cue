import XCTest

/// #679 — end-to-end smoke that selecting a cue row still works (click + keyboard)
/// after the AppKit `selectionHighlightStyle = .none` styling, with a screenshot
/// for the record. The blue-vs-no-blue *pixels* can't be asserted here: the
/// emphasized system highlight only renders in a key/focused window, which
/// XCUITest doesn't provide, so both the fixed and broken states look identical
/// on-screen under test. The fix is actually guarded, focus-independently, by
/// `TableSelectionHighlightStylerTests.test_plainListSelectionHighlight_disablesHighlight_onRealList`
/// (inspects the mounted NSTableView's `selectionHighlightStyle`), and the fill
/// precedence by `CueRowFillTests`.
final class ListSelectionHighlightUITests: OnlyCueUITestCase {

    func test_selectingACueRow_stillWorks() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        let pane = app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch
        XCTAssertTrue(pane.waitForExistence(timeout: 15))

        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.click()
        Thread.sleep(forTimeInterval: 0.3)
        // Keyboard selection still works — the reason for the introspection
        // approach over dropping List(selection:).
        firstRow.typeKey(.downArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(pane.exists)

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "list-selection-no-blue-highlight"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
