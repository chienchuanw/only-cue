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
    /// Marks every Mini Player panel so it can be picked out of the app's
    /// windows (tests, debugging).
    private static let panelIdentifier = NSUserInterfaceItemIdentifier("OnlyCue.MiniPlayerPanel")

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Whether this controller's panel currently holds keyboard focus — the
    /// discriminator the key-monitor gate keys off (#743).
    ///
    /// Since #761 the panel is a `KeyableMiniPanel`, so "the operator selected
    /// the Mini Player" *is* key-window state. Asked of AppKit at event time
    /// rather than cached, so it cannot go stale. Being key also implies the
    /// panel is visible, that this document's main window is not key, and that
    /// no other document's panel is focused — the multi-document scoping the
    /// gate needs.
    ///
    /// This replaces a front-to-back lookup over `NSApp.orderedWindows` that
    /// could never succeed: `orderedWindows` excludes `NSPanel` objects, so the
    /// filter always came back empty and the gate never opened.
    var isKeyMiniPanel: Bool {
        panel?.isKeyWindow == true
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
        let panel = KeyableMiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: MiniPlayerSize.default, height: 84),
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

        // Size to the body's intrinsic height at the default width, then lock the
        // resulting frame height and allow horizontal resize within the range.
        panel.setContentSize(NSSize(width: MiniPlayerSize.default, height: hosting.view.fittingSize.height))
        let lockedHeight = panel.frame.height
        panel.minSize = NSSize(width: MiniPlayerSize.min, height: lockedHeight)
        panel.maxSize = NSSize(width: MiniPlayerSize.max, height: lockedHeight)

        // Restore remembered frame, then clamp its width in case a stale autosave
        // (e.g. the old fixed 620) falls outside the new range.
        panel.setFrameAutosaveName(autosaveName)
        var frame = panel.frame
        frame.size.width = MiniPlayerSize.clamp(frame.size.width)
        frame.size.height = lockedHeight
        panel.setFrame(frame, display: false)

        panel.delegate = panelDelegate
        return panel
    }
}
