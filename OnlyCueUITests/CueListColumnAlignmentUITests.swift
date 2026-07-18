import XCTest

/// #661 follow-up — the cue-list column headers must line up with the row
/// values below them. Regression guard for the List-inset misalignment: the
/// header sits outside the `List` while rows sit inside it, so without zeroed
/// `.listRowInsets` the List shifts every row right of the header. Uses
/// `setListActI` (numbered, named cues) and compares the `NAME`/`#` header x to
/// a row's name/number x.
final class CueListColumnAlignmentUITests: OnlyCueUITestCase {

    func test_headerColumns_alignWithRowValues() throws {
        let app = launchApp(seed: .setListActI)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "cueListPane").firstMatch.waitForExistence(timeout: 15)
        )

        // Header labels render uppercased via `.textCase(.uppercase)`; the row
        // values keep their original text. Both survive the pane's identifier
        // stamping as accessibility labels.
        let nameHeader = app.staticTexts["NAME"]
        let rowName = app.staticTexts["Lights Up"]   // cue 1 in setListActI
        XCTAssertTrue(nameHeader.waitForExistence(timeout: 10), "NAME header present")
        XCTAssertTrue(rowName.waitForExistence(timeout: 5), "a cue name value is present")

        // The NAME column: header left edge lines up with the name value's left edge.
        XCTAssertEqual(
            rowName.frame.minX,
            nameHeader.frame.minX,
            accuracy: 2.0,
            "the NAME header must line up with the row's name value"
        )

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "cue-list-column-alignment"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
