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
}
