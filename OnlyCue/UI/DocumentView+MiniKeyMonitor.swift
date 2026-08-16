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
        let mainKey = NSApp.keyWindow?.canBecomeMain == true
        guard MiniPlaybackGate.shouldHandle(
            panelVisible: miniController.isVisible,
            isFrontmostMini: isMiniFrontmost,
            mainWindowIsKey: mainKey
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
