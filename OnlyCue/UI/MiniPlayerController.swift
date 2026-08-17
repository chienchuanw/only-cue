import AppKit
import SwiftUI

/// A floating Mini Player panel that can become key so clicking it focuses the
/// panel and the playback keyboard shortcuts work (#761). Still always-on-top,
/// but no longer `.nonactivatingPanel`: the operator's mental model is
/// "select the Mini Player → the keyboard drives it". `canBecomeMain` stays
/// false so the document window remains the main window (the key-monitor gate
/// keys off `documentWindow.isKeyWindow`).
final class KeyableMiniPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating Mini Player `NSPanel` for one document window (#748, #761).
/// An always-on-top utility panel that floats above other apps and takes keyboard
/// focus when clicked. Horizontally resizable within `MiniPlayerSize`; width and
/// position are remembered via the frame autosave name.
@MainActor
final class MiniPlayerController {

    private var panel: NSPanel?

    /// Test seam: the live panel, so its AppKit configuration (focus-on-click,
    /// title-bar-only move, resizable width) can be asserted (#761).
    var configuredPanel: NSPanel? { panel }
    /// Marks every Mini Player panel so the front-most-among-minis lookup can
    /// filter `NSApp.orderedWindows` precisely (not "any NSPanel").
    private static let panelIdentifier = NSUserInterfaceItemIdentifier("OnlyCue.MiniPlayerPanel")

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Whether this controller's panel is the front-most *visible* Mini Player
    /// panel across all open documents. This is the multi-document scoping
    /// discriminator used by the key-monitor gate (#743): the Mini Player panels
    /// are non-activating (they never become key), so key-window state cannot
    /// pick a winner — front-to-back order in `NSApp.orderedWindows` does.
    /// TRUE for the sole panel when a single document is open, and still TRUE
    /// while this document's main window is collapsed (the panel stays visible).
    var isFrontmostMiniPanel: Bool {
        guard let panel, panel.isVisible else { return false }
        let visibleMiniPanels = NSApp.orderedWindows.filter {
            $0.identifier == Self.panelIdentifier && $0.isVisible
        }
        return visibleMiniPanels.first === panel
    }

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
        onUserClosedPanel = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
    }

    private func makePanel(rootView: some View, autosaveName: String) -> NSPanel {
        // Host the body width-flexible so it reflows across the resize range; the
        // panel — not a fixed `.frame(width:)` — governs the width now (#761).
        let hosting = NSHostingController(rootView: AnyView(rootView))
        let contentHeight = hosting.sizeThatFits(
            in: NSSize(width: MiniPlayerSize.default, height: .greatestFiniteMagnitude)
        ).height
        let panel = KeyableMiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: MiniPlayerSize.default, height: contentHeight),
            styleMask: [.titled, .closable, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        // Only the title bar moves the window; the body is left to the scrub
        // gesture so dragging the knob seeks instead of moving the panel (#761).
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.identifier = Self.panelIdentifier
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: MiniPlayerSize.default, height: contentHeight))

        // Lock height, allow horizontal resize within the policy range.
        let frameHeight = panel.frame.height
        panel.minSize = NSSize(width: MiniPlayerSize.min, height: frameHeight)
        panel.maxSize = NSSize(width: MiniPlayerSize.max, height: frameHeight)

        // Restore remembered frame, then clamp its width in case a stale autosave
        // (e.g. the old fixed 620) falls outside the new range.
        panel.setFrameAutosaveName(autosaveName)
        var frame = panel.frame
        frame.size.width = MiniPlayerSize.clamp(frame.size.width)
        frame.size.height = frameHeight
        panel.setFrame(frame, display: false)

        panel.delegate = panelDelegate
        return panel
    }
}
