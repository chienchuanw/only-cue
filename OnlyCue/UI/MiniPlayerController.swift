import AppKit
import SwiftUI

/// Owns the floating Mini Player `NSPanel` for one document window (#748).
/// A non-activating, always-on-top utility panel: it floats above other apps
/// and clicking its controls does not steal focus from whatever is frontmost —
/// the behaviour a live operator wants. Fixed compact width; position is
/// remembered via the frame autosave name.
@MainActor
final class MiniPlayerController {

    private var panel: NSPanel?
    private static let width: CGFloat = 620

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Invoked when the user dismisses the panel via its close (X) button.
    /// Not invoked when `hide()` (orderOut) is called programmatically.
    var onUserClosedPanel: (() -> Void)?

    private lazy var panelDelegate = PanelDelegate { [weak self] in
        self?.onUserClosedPanel?()
    }

    private final class PanelDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }

    func toggle(rootView: some View, title: String, autosaveName: String) {
        if isVisible {
            hide()
        } else {
            show(rootView: rootView, title: title, autosaveName: autosaveName)
        }
    }

    func show(rootView: some View, title: String, autosaveName: String) {
        let panel = self.panel ?? makePanel(rootView: rootView, autosaveName: autosaveName)
        self.panel = panel
        panel.title = title
        panel.orderFront(nil)
    }

    func setTitle(_ title: String) {
        panel?.title = title
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Tear down with the owning document window.
    func close() {
        panel?.close()
        panel = nil
    }

    private func makePanel(rootView: some View, autosaveName: String) -> NSPanel {
        let hosting = NSHostingController(rootView: AnyView(rootView.frame(width: Self.width)))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 84),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        panel.setContentSize(hosting.view.fittingSize)
        panel.setFrameAutosaveName(autosaveName)
        panel.delegate = panelDelegate
        return panel
    }
}
