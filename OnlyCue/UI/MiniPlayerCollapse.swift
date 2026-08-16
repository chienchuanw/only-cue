import Foundation

/// Collapse-to-Mini decisions (#743). Invariant: while a document is open it
/// never has zero visible surfaces, and an unsaved document is never silently
/// discarded — so the main window's close button collapses to the Mini Player
/// (hide) whenever the Mini Player is visible, and closing the Mini Player
/// restores a hidden main window instead of leaving nothing.
enum MiniPlayerCollapse {

    enum CloseOutcome { case collapseToMini, closeDocument }
    enum MiniCloseOutcome { case restoreMainWindow, justCloseMini }

    static func onMainWindowClose(miniVisible: Bool) -> CloseOutcome {
        miniVisible ? .collapseToMini : .closeDocument
    }

    static func onMiniClose(mainWindowHidden: Bool) -> MiniCloseOutcome {
        mainWindowHidden ? .restoreMainWindow : .justCloseMini
    }
}
