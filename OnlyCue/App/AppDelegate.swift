import AppKit
import SwiftUI

/// Owns the welcome / start window for the launch flow (#591).
///
/// A SwiftUI `Window` scene does not reliably auto-open at launch inside a
/// `DocumentGroup` app on macOS 14 (the document scene owns launch), so the
/// welcome window is an AppKit `NSWindow` hosting the SwiftUI `StartView`.
///
/// Launch behavior: `applicationShouldOpenUntitledFile` returns false to block
/// the default blank untitled document. On macOS 14 that still leaves the
/// app-centric **Open panel** showing next to the welcome window (the panel is
/// `DocumentGroup`'s own no-document launch behavior, not gated by the untitled
/// delegate, and forcing `NSShowAppCentricOpenPanelInsteadOfUntitledFile`
/// off merely swaps it for a blank Untitled document). So the launch Open panel
/// is dismissed here before the welcome window is shown (#601).
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var welcomeWindow: NSWindow?

    /// True when launched by a UI test, which opens its own seeded document and
    /// must not get the welcome window.
    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("--ui-test") }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isUITestLaunch else { return }
        resolveLaunchPresentation(attemptsRemaining: 25)
    }

    // Dock-icon click / reopen with no visible windows → show the welcome window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcomeWindow() }
        return true
    }

    /// Dismiss `DocumentGroup`'s launch Open panel (it appears a beat after
    /// launch), then show the welcome window — unless a real document was
    /// restored/opened, in which case neither is needed. Polls briefly because
    /// the panel isn't up yet in the first `didFinishLaunching` tick.
    @MainActor
    private func resolveLaunchPresentation(attemptsRemaining: Int) {
        // A restored or document-launched window means no welcome screen.
        if NSDocumentController.shared.documents.contains(where: { $0.fileURL != nil }) { return }

        if let panel = NSApp.windows.first(where: { $0 is NSOpenPanel }) as? NSOpenPanel {
            panel.cancel(nil)
            showWelcomeWindow()
            return
        }

        guard attemptsRemaining > 0 else {
            // Panel never appeared (or already gone) — still show the welcome.
            showWelcomeWindow()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.resolveLaunchPresentation(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    @MainActor
    func showWelcomeWindow() {
        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: StartView(onOpenProject: { [weak self] in self?.closeWelcomeWindow() })
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Welcome to OnlyCue")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: StartWindowMetrics.width, height: StartWindowMetrics.height))
        window.center()
        window.isReleasedWhenClosed = false
        welcomeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func closeWelcomeWindow() {
        welcomeWindow?.close()
    }
}
