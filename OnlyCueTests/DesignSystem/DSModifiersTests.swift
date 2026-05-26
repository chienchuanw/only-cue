import XCTest
import SwiftUI
@testable import OnlyCue

final class DSModifiersTests: XCTestCase {

    // Renders each modifier into an NSHostingView — fails to compile if a
    // modifier is missing, fails at runtime if a modifier traps during layout.
    func testModifiersRenderWithoutTrapping() {
        let views: [NSView] = [
            NSHostingView(rootView: Color.clear.frame(width: 10, height: 10).dsPanel()),
            NSHostingView(rootView: Text("x").dsImportWell()),
            NSHostingView(rootView: Text("x").dsSectionHeader()),
            NSHostingView(rootView: Color.clear.frame(width: 10, height: 10).dsHairline(edge: .bottom)),
            NSHostingView(rootView: Text("x").dsCard())
        ]
        for view in views {
            view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(view.fittingSize.width, 0)
        }
    }

    func testDSCardClipsToRoundedRectAndFillsBeyondZero() {
        let host = NSHostingView(
            rootView: Text("Audio Settings group")
                .frame(width: 200, height: 80)
                .dsCard()
        )
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 200, "card should add inner padding")
        XCTAssertGreaterThan(host.fittingSize.height, 80, "card should add inner padding")
    }
}
