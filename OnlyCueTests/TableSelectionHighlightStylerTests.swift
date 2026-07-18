import AppKit
import XCTest
@testable import OnlyCue

@MainActor
final class TableSelectionHighlightStylerTests: XCTestCase {

    func test_disableSystemHighlight_findsEnclosingTable_andSetsNone() {
        // A probe buried under a row view under the table — the shape SwiftUI's
        // List produces. The walker must reach the table and kill its highlight.
        let table = NSTableView()
        table.selectionHighlightStyle = .regular
        let rowView = NSView()
        let probe = NSView()
        rowView.addSubview(probe)
        table.addSubview(rowView)

        let styled = TableSelectionHighlightStyler.disableSystemHighlight(from: probe)

        XCTAssertEqual(table.selectionHighlightStyle, .none)
        XCTAssertIdentical(styled, table)
    }

    func test_disableSystemHighlight_returnsNil_whenNoEnclosingTable() {
        let container = NSView()
        let probe = NSView()
        container.addSubview(probe)

        XCTAssertNil(TableSelectionHighlightStyler.disableSystemHighlight(from: probe))
    }
}
