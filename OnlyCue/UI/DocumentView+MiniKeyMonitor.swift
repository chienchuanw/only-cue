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
        // - `mainWindowIsKey` is this document's own window (not any app window),
        //   so a collapsed / behind main window reads false and the gate can fire.
        // - `isFrontmostDocument` is the panel's front-to-back rank among all
        //   Mini Player panels, which stays true when this document is the sole
        //   or front document even while its main window is collapsed, and yields
        //   to another document whose panel is in front.
        guard MiniPlaybackGate.shouldHandle(
            panelVisible: miniController.isVisible,
            isFrontmostDocument: miniController.isFrontmostMiniPanel,
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
