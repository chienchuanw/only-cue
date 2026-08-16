import AppKit
import SwiftUI
import XCTest
@testable import OnlyCue

/// Reproduces the #750 bug condition with realistic media names — items whose
/// `resolvedName` begins with a digit ("1_intro", "2_break", "10_finale") are
/// exactly what makes `NSTableView`'s built-in type-select swallow the matching
/// digit cue hotkey. The fix makes the media list's backing table refuse first
/// responder, so it can never receive the `keyDown` that would type-select, and
/// the digit falls through to cue creation instead.
///
/// These assertions are focus-independent (they check responder *capability*,
/// not live key events), so they run in CI without UI automation.
@MainActor
final class ItemListPaneTypeSelectTests: XCTestCase {

    func test_mediaListWithDigitLeadingNames_tableRefusesFirstResponder() throws {
        let document = Self.documentWithDigitLeadingMedia()

        // Sanity: the bug only bites when a row label starts with the pressed
        // digit — pin that these names actually do.
        let names = document.model.items.map(\.resolvedName)
        XCTAssertEqual(names, ["1_intro", "2_break", "10_finale"])
        for name in names {
            XCTAssertTrue(
                name.first?.isNumber == true,
                "\(name) must start with a digit to reproduce the type-select clash"
            )
        }

        let table = try mountAndFindTable(for: document)

        XCTAssertTrue(
            table.refusesFirstResponder,
            "the media list's table must refuse first responder so type-select can't fire"
        )
        // The behavioural consequence: a table that refuses first responder can
        // never accept it, so it will not receive keyDown — type-select on the
        // digit-named rows is physically impossible.
        XCTAssertFalse(
            table.acceptsFirstResponder,
            "a first-responder-refusing table must not accept first responder"
        )
    }

    func test_mediaListTable_doesNotBecomeWindowFirstResponder() throws {
        let document = Self.documentWithDigitLeadingMedia()
        let (window, table) = try mountInWindow(for: document)
        defer { window.orderOut(nil) }

        // Even asked directly, the refusing table must not end up focused —
        // AppKit may report success by focusing the window instead, but the
        // table itself must never be the first responder that receives keyDown.
        window.makeFirstResponder(table)

        XCTAssertNotIdentical(
            window.firstResponder as AnyObject,
            table,
            "the table must not end up as the window's first responder"
        )
    }

    // MARK: - Fixtures

    private static func documentWithDigitLeadingMedia() -> CueListDocument {
        let document = CueListDocument()
        CueCommands.addItems(
            ["1_intro", "2_break", "10_finale"].map(makeItem(name:)),
            to: document,
            undoManager: nil
        )
        return document
    }

    private static func makeItem(name: String) -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: name,
                kind: .audio,
                duration: 30,
                bookmarkData: Data([0x00])
            ),
            cues: []
        )
    }

    // MARK: - Hosting

    private func mountInWindow(for document: CueListDocument) throws -> (NSWindow, NSTableView) {
        let hosting = NSHostingView(rootView: ItemListPane(document: document, onDropURLs: { _ in }))
        hosting.frame = CGRect(x: 0, y: 0, width: 260, height: 400)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)

        var table: NSTableView?
        let mounted = expectation(description: "media list table mounted and refusing first responder")
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

        let found = try XCTUnwrap(table, "ItemListPane should mount an NSTableView for its List")
        return (window, found)
    }

    private func mountAndFindTable(for document: CueListDocument) throws -> NSTableView {
        let (window, table) = try mountInWindow(for: document)
        window.orderOut(nil)
        return table
    }

    private static func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let found = findTableView(in: subview) { return found }
        }
        return nil
    }
}
