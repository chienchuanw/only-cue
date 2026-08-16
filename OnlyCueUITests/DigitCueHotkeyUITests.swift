import XCTest

/// End-to-end guard for #750: with media whose names start with digits, the
/// sidebar `NSTableView`'s built-in type-select used to swallow a digit keypress
/// (jumping to the matching media) before it could reach the window-level cue
/// hotkey — so no cue was created. The fix makes the media list refuse first
/// responder; pressing the digit must now create a cue instead.
///
/// Runs on push to dev/main only (UI tests are gated off PRs in CI).
final class DigitCueHotkeyUITests: OnlyCueUITestCase {

    func test_digitKey_createsCue_notTypeSelect_withDigitLeadingMediaNames() throws {
        let app = launchApp(seed: .digitLeadingMediaTypeSelect)
        let window = try waitForSeedWindow(in: app)

        // The seeded sidebar (active "2_break", plus "1_intro" / "3_finale").
        let firstMediaRow = window.descendants(matching: .any)
            .matching(identifier: "itemRow").firstMatch
        XCTAssertTrue(
            firstMediaRow.waitForExistence(timeout: 15),
            "seeded media rows should appear in the sidebar"
        )

        // The active item starts cue-free.
        XCTAssertEqual(dedupedCueRowCount(in: window), 0, "active item should start with no cues")

        // Click the active media row so the sidebar table holds keyboard focus —
        // the exact state in which its type-select used to eat the digit.
        firstMediaRow.click()
        Thread.sleep(forTimeInterval: 0.3)

        // Press "1": the cue type is bound to hotkey 1, so this must create a
        // cue. Before the fix, the table's type-select would instead jump to
        // "1_intro" and consume the key, leaving the cue list empty.
        app.typeKey("1", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertEqual(
            dedupedCueRowCount(in: window),
            1,
            "pressing '1' must create a cue — proving the media list no longer swallows the digit"
        )
    }

    /// SwiftUI wraps each identified row in two AX nodes, so count distinct
    /// `cueRow-<id>` identifiers rather than raw element matches.
    private func dedupedCueRowCount(in window: XCUIElement) -> Int {
        let rows = window.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'cueRow-'"))
            .allElementsBoundByIndex
        var seen = Set<String>()
        for row in rows where !row.identifier.isEmpty {
            seen.insert(row.identifier)
        }
        return seen.count
    }
}
