import AppKit
import SwiftUI
import XCTest
@testable import OnlyCue

@MainActor
final class TableSelectionHighlightStylerTests: XCTestCase {

    // MARK: - Integration: proves the probe reaches a real SwiftUI List's table

    /// The unit tests above prove the *walk*; this proves the *premise* — that
    /// `.plainListSelectionHighlight()` on a real `List` row parents its probe
    /// under the backing `NSTableView` so the walk actually disables the system
    /// highlight. Focus-independent (unlike the on-screen blue, which only
    /// renders in a key window), so it can run in CI (#679).
    func test_plainListSelectionHighlight_disablesHighlight_onRealList() throws {
        struct Harness: View {
            var body: some View {
                List(selection: .constant(Set<Int>())) {
                    ForEach(0..<5, id: \.self) { index in
                        Text("Row \(index)").plainListSelectionHighlight()
                    }
                }
            }
        }

        let hosting = NSHostingView(rootView: Harness())
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        // Poll on the main runloop the XCTest-safe way (an expectation pumped by
        // `wait`, never a nested `RunLoop.run`, which crashes the shared test
        // process) until SwiftUI mounts the table and the probe's
        // viewDidMoveToWindow fires.
        var table: NSTableView?
        let mounted = expectation(description: "table style disabled")
        func poll(_ remaining: Int) {
            hosting.layoutSubtreeIfNeeded()
            table = Self.findTableView(in: hosting)
            if table?.selectionHighlightStyle == NSTableView.SelectionHighlightStyle.none || remaining <= 0 {
                mounted.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll(remaining - 1) }
        }
        poll(60)
        wait(for: [mounted], timeout: 5)

        let found = try XCTUnwrap(table, "the SwiftUI List should mount an NSTableView")
        XCTAssertEqual(
            found.selectionHighlightStyle,
            NSTableView.SelectionHighlightStyle.none,
            "the probe must disable the enclosing table's system selection highlight"
        )
    }

    private static func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let found = findTableView(in: subview) { return found }
        }
        return nil
    }

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

    // MARK: - Type-select suppression (#750)

    /// The media list's backing `NSTableView` is the window's de-facto first
    /// responder, so its built-in type-select swallows digit cue hotkeys before
    /// they reach the window-level shortcuts (#750). Refusing first responder
    /// stops the table from ever receiving `keyDown`, killing type-select and
    /// letting the digit fall through to cue creation.
    func test_disableTypeSelect_findsEnclosingTable_andRefusesFirstResponder() {
        let table = NSTableView()
        XCTAssertFalse(table.refusesFirstResponder)
        let rowView = NSView()
        let probe = NSView()
        rowView.addSubview(probe)
        table.addSubview(rowView)

        let styled = TableSelectionHighlightStyler.disableTypeSelect(from: probe)

        XCTAssertTrue(table.refusesFirstResponder)
        XCTAssertIdentical(styled, table)
    }

    func test_disableTypeSelect_returnsNil_whenNoEnclosingTable() {
        let container = NSView()
        let probe = NSView()
        container.addSubview(probe)

        XCTAssertNil(TableSelectionHighlightStyler.disableTypeSelect(from: probe))
    }

    /// Integration: proves `.plainListSelectionHighlight(disableTypeSelect: true)`
    /// on a real `List` row reaches the backing `NSTableView` and refuses first
    /// responder — focus-independent, so it runs in CI (#750).
    func test_plainListSelectionHighlight_disableTypeSelect_refusesFirstResponder_onRealList() throws {
        struct Harness: View {
            var body: some View {
                List(selection: .constant(Set<Int>())) {
                    ForEach(0..<5, id: \.self) { index in
                        Text("\(index)_row")
                            .plainListSelectionHighlight(disableTypeSelect: true)
                    }
                }
            }
        }

        let hosting = NSHostingView(rootView: Harness())
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        var table: NSTableView?
        let mounted = expectation(description: "table refuses first responder")
        func poll(_ remaining: Int) {
            hosting.layoutSubtreeIfNeeded()
            table = Self.findTableView(in: hosting)
            if table?.refusesFirstResponder == true || remaining <= 0 {
                mounted.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll(remaining - 1) }
        }
        poll(60)
        wait(for: [mounted], timeout: 5)

        let found = try XCTUnwrap(table, "the SwiftUI List should mount an NSTableView")
        XCTAssertTrue(
            found.refusesFirstResponder,
            "the probe must make the enclosing table refuse first responder to kill type-select"
        )
    }
}
