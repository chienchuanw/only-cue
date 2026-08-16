import XCTest
@testable import OnlyCue

final class MiniPlaybackGateTests: XCTestCase {

    // MARK: - Decision (pure boolean truth table)

    func test_handlesWhenFrontmostDocumentAndMainNotKey() {
        XCTAssertTrue(MiniPlaybackGate.shouldHandle(
            panelVisible: true, isFrontmostDocument: true, mainWindowIsKey: false
        ))
    }

    func test_yieldsWhenMainWindowIsKey() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(
            panelVisible: true, isFrontmostDocument: true, mainWindowIsKey: true
        ))
    }

    func test_yieldsWhenPanelHidden() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(
            panelVisible: false, isFrontmostDocument: true, mainWindowIsKey: false
        ))
    }

    func test_yieldsWhenNotFrontmostDocument() {
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(
            panelVisible: true, isFrontmostDocument: false, mainWindowIsKey: false
        ))
    }

    // MARK: - Input-derivation cases (the wiring the old test could not catch)
    //
    // These express the four behaviours the live wiring must satisfy, using the
    // same `Inputs` struct the key monitor builds from its live objects
    // (`panelVisible` = miniController.isVisible, `isFrontmostDocument` =
    // miniController.isFrontmostMiniPanel, `mainWindowIsKey` =
    // documentWindow?.isKeyWindow). The window-key read itself is runtime-only
    // (needs a live NSWindow), but the decision from these derived inputs is not.

    func test_collapsedMainWindow_panelVisibleFrontmost_handles() {
        // Collapsed main window -> its own window is not key; panel stays visible
        // and is the sole/front mini -> handle.
        let inputs = MiniPlaybackGate.Inputs(
            panelVisible: true, isFrontmostDocument: true, mainWindowIsKey: false
        )
        XCTAssertTrue(MiniPlaybackGate.shouldHandle(inputs))
    }

    func test_mainWindowKey_yields() {
        let inputs = MiniPlaybackGate.Inputs(
            panelVisible: true, isFrontmostDocument: true, mainWindowIsKey: true
        )
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(inputs))
    }

    func test_panelHidden_yields() {
        let inputs = MiniPlaybackGate.Inputs(
            panelVisible: false, isFrontmostDocument: true, mainWindowIsKey: false
        )
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(inputs))
    }

    func test_otherDocumentIsFrontmost_yields() {
        // Two documents open, the OTHER document's panel is front -> this one
        // must not also fire (no double-dispatch).
        let inputs = MiniPlaybackGate.Inputs(
            panelVisible: true, isFrontmostDocument: false, mainWindowIsKey: false
        )
        XCTAssertFalse(MiniPlaybackGate.shouldHandle(inputs))
    }
}
