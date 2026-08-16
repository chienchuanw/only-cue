import Foundation

/// Decides whether the Mini Player's key monitor should handle a playback key or
/// yield it to the main window (#743, Approach A). Handle only when the Mini
/// Player is the visible frontmost surface and no document window is key —
/// otherwise the main window's own SwiftUI shortcuts (which already yield to
/// inline text fields) take the key.
enum MiniPlaybackGate {
    static func shouldHandle(panelVisible: Bool, isFrontmostMini: Bool, mainWindowIsKey: Bool) -> Bool {
        panelVisible && isFrontmostMini && !mainWindowIsKey
    }
}
