import AppKit
import SwiftUI

extension DocumentView {

    /// Installs the app-local key-down monitor that lets the Mini Player receive
    /// playback shortcuts when it is the frontmost surface (#743). Idempotent.
    func startMiniKeyMonitor() {
        guard miniKeyMonitor == nil else { return }
        miniKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            self.handleMiniKey(event) ? nil : event
        }
    }

    func stopMiniKeyMonitor() {
        if let token = miniKeyMonitor { NSEvent.removeMonitor(token) }
        miniKeyMonitor = nil
    }

    /// Returns true when the event was handled (and should be swallowed).
    private func handleMiniKey(_ event: NSEvent) -> Bool {
        // Derive the gate inputs from THIS document's own live objects:
        // - `isFrontmostDocument` is the panel's own key-window state: the
        //   operator selects the Mini Player and the keyboard follows focus.
        //   That scopes multi-document for free (only one panel app-wide can be
        //   key) and stays true while this document's main window is collapsed.
        // - `panelVisible` / `mainWindowIsKey` are implied by a key panel and
        //   kept as belt-and-braces.
        guard MiniPlaybackGate.shouldHandle(
            panelVisible: miniController.isVisible,
            isFrontmostDocument: miniController.isKeyMiniPanel,
            mainWindowIsKey: documentWindow?.isKeyWindow == true
        ) else { return false }

        guard let chord = MiniKeyChord.from(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            flags: event.modifierFlags
        ), let action = MiniPlaybackKeymap.action(for: chord, keymap: KeymapStore.shared.keymap) else {
            return false
        }

        MiniPlaybackActions(
            engine: engine,
            document: document,
            context: miniContext,
            ltcEnabled: ltcRoutingStore.settings.isEnabled,
            seekTaskBox: seekBox
        ).perform(action)
        return true
    }
}
