import XCTest

/// Phase-A workspace behaviour that is only observable through the running
/// window: the inspector's collapse toggle and the View ▸ Workspace submenu.
/// Divider *dragging* is exercised by hand (the spec's outstanding manual
/// check) — a synthetic drag on a 1pt hit area is flaky enough to be worse
/// than no coverage.
final class WorkspaceLayoutUITests: OnlyCueUITestCase {

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scenario: Hiding the inspector
    ///   Given the inspector is visible
    ///   When the designer presses ⌥⌘I
    ///   Then the inspector is removed from the layout
    ///   And pressing ⌥⌘I again restores it
    func test_optionCommandI_togglesTheInspector() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)

        let inspector = element(app, "cueListPane")
        XCTAssertTrue(
            inspector.waitForExistence(timeout: 15),
            "the cue-list inspector should be visible on a seeded document"
        )

        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(
            waitForDisappearance(of: inspector, timeout: 5),
            "⌥⌘I should hide the inspector"
        )

        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(
            inspector.waitForExistence(timeout: 5),
            "⌥⌘I should restore the inspector"
        )
    }

    /// The divider is present and exposes its width to accessibility, so a
    /// VoiceOver user can tell how wide the inspector is.
    func test_inspectorDivider_isExposedToAccessibility() throws {
        let app = launchApp(seed: .threeCuesAt1And3And6)
        let divider = element(app, "inspectorDivider")
        XCTAssertTrue(divider.waitForExistence(timeout: 15))
        XCTAssertFalse(divider.label.isEmpty, "the divider needs an accessibility label")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}
