import Foundation

/// Decides whether the Mini Player's key monitor should handle a playback key or
/// yield it to the main window (#743, Approach A). Handle only when the Mini
/// Player is the visible frontmost surface and this document's own main window is
/// NOT key — otherwise the main window's own SwiftUI shortcuts (which already
/// yield to inline text fields) take the key.
enum MiniPlaybackGate {

    /// The three raw inputs to the gate. Extracted so the *derivation* of these
    /// from live windows can be exercised in a unit test without an `NSWindow`
    /// (the bug in #743 was dead wiring that the boolean-only test never caught).
    struct Inputs: Equatable {
        /// The Mini Player panel is on screen for this document.
        var panelVisible: Bool
        /// This document is the frontmost OnlyCue surface — the multi-document
        /// scoping signal. TRUE for exactly one open document at a time, and
        /// crucially still TRUE for this document when its main window is
        /// collapsed / behind (so the gate can fire in the collapsed case).
        var isFrontmostDocument: Bool
        /// This document's OWN main window currently holds key. When true the
        /// user is driving the main window and its shortcuts win.
        var mainWindowIsKey: Bool
    }

    static func shouldHandle(_ inputs: Inputs) -> Bool {
        inputs.panelVisible && inputs.isFrontmostDocument && !inputs.mainWindowIsKey
    }

    static func shouldHandle(panelVisible: Bool, isFrontmostDocument: Bool, mainWindowIsKey: Bool) -> Bool {
        shouldHandle(Inputs(
            panelVisible: panelVisible,
            isFrontmostDocument: isFrontmostDocument,
            mainWindowIsKey: mainWindowIsKey
        ))
    }
}
