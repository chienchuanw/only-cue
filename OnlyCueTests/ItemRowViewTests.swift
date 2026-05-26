import XCTest
import SwiftUI
import AppKit
@testable import OnlyCue

/// Pins the inline Edit Media affordance on the sidebar row (#421, audit
/// §13). The button must be present in the AX tree under a stable identifier
/// when an `onEdit` callback is provided, and must invoke that callback.
@MainActor
final class ItemRowViewTests: XCTestCase {

    /// Asserts the row gets visibly wider when `onEdit` is wired, which is
    /// only true if the conditional pencil button is rendering. SwiftUI
    /// buttons inside `NSHostingView` don't reliably surface as discrete
    /// NSButton / NSAccessibility children in a unit-test harness — actual
    /// click behavior is therefore exercised by the new XCUITest path in
    /// `MediaEditSheetUITests`.
    func test_row_widerWhenInlineEditButtonRendered() {
        let item = Self.makeAudioItem()

        let withButton = NSHostingView(rootView: ItemRowView(item: item, onEdit: {}))
        let withoutButton = NSHostingView(rootView: ItemRowView(item: item, onEdit: nil))
        withButton.layoutSubtreeIfNeeded()
        withoutButton.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(
            withButton.fittingSize.width,
            withoutButton.fittingSize.width,
            "Row with onEdit callback must render the pencil button (and so be wider)."
        )
    }

    // MARK: helpers

    private static func makeAudioItem() -> MediaItem {
        MediaItem(
            id: UUID(),
            media: MediaReference(
                displayName: "test.m4a",
                kind: .audio,
                duration: 30,
                bookmarkData: Data()
            ),
            cues: []
        )
    }

}
