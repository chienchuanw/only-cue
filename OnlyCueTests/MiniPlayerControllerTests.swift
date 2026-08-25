import AppKit
import SwiftUI
import XCTest
@testable import OnlyCue

/// In-process runtime coverage for the Mini Player panel lifecycle (#748).
/// Exercises `MiniPlayerController` directly (create / show / hide / toggle) so
/// the NSPanel management is verified without a foregroundable GUI session or
/// XCUITest — complementing the CI-skipped `MiniPlayerUITests` smoke test.
@MainActor
final class MiniPlayerControllerTests: XCTestCase {

    private func root() -> some View { Text("mini").frame(width: 620, height: 60) }

    func test_startsHidden() {
        let controller = MiniPlayerController()
        XCTAssertFalse(controller.isVisible)
        controller.close()
    }

    func test_showThenHide() {
        let controller = MiniPlayerController()
        controller.show(rootView: root(), title: "Clip.wav", autosaveName: "OnlyCue.MiniPlayerTest")
        XCTAssertTrue(controller.isVisible, "show() should make the panel visible")
        controller.hide()
        XCTAssertFalse(controller.isVisible, "hide() should order the panel out")
        controller.close()
    }

    func test_toggleFlipsVisibility() {
        let controller = MiniPlayerController()
        controller.toggle(rootView: root(), title: "Clip.wav", autosaveName: "OnlyCue.MiniPlayerTest")
        XCTAssertTrue(controller.isVisible)
        controller.toggle(rootView: root(), title: "Clip.wav", autosaveName: "OnlyCue.MiniPlayerTest")
        XCTAssertFalse(controller.isVisible)
        controller.close()
    }

    func test_reshowReusesPanelAndUpdatesTitle() {
        let controller = MiniPlayerController()
        controller.show(rootView: root(), title: "First.wav", autosaveName: "OnlyCue.MiniPlayerTest")
        controller.hide()
        controller.show(rootView: root(), title: "Second.wav", autosaveName: "OnlyCue.MiniPlayerTest")
        XCTAssertTrue(controller.isVisible)
        controller.close()
        XCTAssertFalse(controller.isVisible, "close() should tear the panel down")
    }

    // MARK: - Key-window derivation (#770)

    /// Pins the AppKit fact behind #770: `NSApp.orderedWindows` omits `NSPanel`
    /// objects, so a "front-most among the Mini Player panels" lookup over it
    /// can never match — it silently reports `false` forever. `NSApp.windows`
    /// is the collection that does include panels.
    func test_visiblePanel_isInAppWindows_butNeverInOrderedWindows() throws {
        let controller = MiniPlayerController()
        defer { controller.close() }
        controller.show(rootView: root(), title: "Clip.wav", autosaveName: "OnlyCue.MiniPlayerTest")
        let panel = try XCTUnwrap(controller.configuredPanel)

        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(NSApp.windows.contains(panel), "NSApp.windows should include the Mini Player panel")
        XCTAssertFalse(
            NSApp.orderedWindows.contains(panel),
            "NSApp.orderedWindows excludes NSPanel — never look a Mini Player panel up through it"
        )
    }

    func test_isKeyMiniPanel_isFalseWhenPanelHidden() {
        let controller = MiniPlayerController()
        defer { controller.close() }
        XCTAssertFalse(controller.isKeyMiniPanel, "no panel yet -> not key")
        controller.show(rootView: root(), title: "Clip.wav", autosaveName: "OnlyCue.MiniPlayerTest")
        controller.hide()
        XCTAssertFalse(controller.isKeyMiniPanel, "an ordered-out panel cannot be key")
    }

    // The true-positive case — a *key* panel reporting `isKeyMiniPanel == true`
    // — is deliberately not tested here. The unit-test host never becomes the
    // active app (measured: `NSApp.isActive` stays false through repeated
    // `activate(ignoringOtherApps:)` calls), and no window of an inactive app
    // can be key, so such a test would skip on every machine and every CI run.
    // A test that can never execute is coverage theatre — the same illusion
    // that let #770 ship. It lives in `MiniPlayerUITests` instead, where the
    // app really does hold focus.
}
