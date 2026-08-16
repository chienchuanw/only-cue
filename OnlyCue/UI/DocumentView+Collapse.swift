import AppKit
import SwiftUI

extension DocumentView {

    /// Hides the main document window, leaving the Mini Player as the only
    /// visible surface. Sets `isMainWindowCollapsed` so the Mini Player's own
    /// close path knows to restore the window rather than just dismiss (#743).
    func collapseMainWindow() {
        documentWindow?.orderOut(nil)
        isMainWindowCollapsed = true
    }

    /// Shows the main document window again after it was collapsed to the Mini
    /// Player. Clears `isMainWindowCollapsed`.
    func restoreMainWindow() {
        documentWindow?.makeKeyAndOrderFront(nil)
        isMainWindowCollapsed = false
    }
}
