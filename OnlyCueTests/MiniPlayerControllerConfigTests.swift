import AppKit
import SwiftUI
import XCTest
@testable import OnlyCue

/// Regression guards for the Mini Player panel's AppKit configuration (#761):
/// focus-on-click (key-capable, not non-activating), title-bar-only move, and
/// resizable width clamped to `MiniPlayerSize`. These lock the panel setup that a
/// boolean-only or lifecycle-only test would not catch.
@MainActor
final class MiniPlayerControllerConfigTests: XCTestCase {

    private func makeShownPanel() -> (MiniPlayerController, NSPanel) {
        let controller = MiniPlayerController()
        controller.show(
            rootView: Text("mini").frame(height: 60),
            title: "Clip.wav",
            autosaveName: "OnlyCue.MiniPlayerConfigTest"
        )
        guard let panel = controller.configuredPanel else {
            XCTFail("controller should expose its configured panel after show()")
            return (controller, NSPanel())
        }
        return (controller, panel)
    }

    func test_panelIsKeyCapable_forClickToFocus() {
        let (controller, panel) = makeShownPanel()
        defer { controller.close() }
        XCTAssertTrue(panel.canBecomeKey, "clicking the Mini Player must be able to focus it")
        XCTAssertFalse(
            panel.styleMask.contains(.nonactivatingPanel),
            "non-activating panel would keep the app inactive and starve the key monitor"
        )
    }

    func test_titleBarOnlyMove() {
        let (controller, panel) = makeShownPanel()
        defer { controller.close() }
        XCTAssertFalse(
            panel.isMovableByWindowBackground,
            "body drag must not move the window (it would fight the scrub gesture)"
        )
    }

    func test_resizableWidthClampedToPolicy() {
        let (controller, panel) = makeShownPanel()
        defer { controller.close() }
        XCTAssertTrue(panel.styleMask.contains(.resizable), "panel must be horizontally resizable")
        XCTAssertEqual(panel.minSize.width, MiniPlayerSize.min)
        XCTAssertEqual(panel.maxSize.width, MiniPlayerSize.max)
        XCTAssertEqual(panel.minSize.height, panel.maxSize.height, "height is locked")
        XCTAssertGreaterThan(panel.minSize.height, 0)
    }

    func test_stillFloatingOnTop() {
        let (controller, panel) = makeShownPanel()
        defer { controller.close() }
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
    }
}
