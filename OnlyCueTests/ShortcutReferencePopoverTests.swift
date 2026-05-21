import SwiftUI
import XCTest
@testable import OnlyCue

final class ShortcutReferencePopoverTests: XCTestCase {

    // Renders the popover into an NSHostingView — fails to compile if the type
    // is missing, fails at runtime if it traps during layout.
    func testPopoverRendersWithoutTrapping() {
        let view = NSHostingView(rootView: ShortcutReferencePopover())
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.width, 0)
    }
}
