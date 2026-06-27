import AppKit
import SwiftUI

/// Owns the welcome / start window for the launch flow (#591).
///
/// A SwiftUI `Window` scene does not reliably auto-open at launch inside a
/// `DocumentGroup` app on macOS 14 (the document scene owns launch), so the
/// welcome window is an AppKit `NSWindow` hosting the SwiftUI `StartView`. The
/// delegate also suppresses the default blank untitled document so the welcome
/// window is what the user sees, and re-shows it on reopen when nothing is open.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var welcomeWindow: NSWindow?

    private enum Metrics {
        static let width: CGFloat = 720
        static let height: CGFloat = 460
    }

    // Stop macOS from auto-creating a blank untitled document at launch/reopen.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI tests open their own seeded document — don't race them with the
        // welcome window.
        guard !Self.isUITestLaunch else { return }
        // Defer so any state-restored document loads first; only show the
        // welcome window when launch produced no open document.
        DispatchQueue.main.async { [weak self] in
            guard NSDocumentController.shared.documents.isEmpty else { return }
            self?.showWelcomeWindow()
        }
    }

    /// True when launched by a UI test (which seeds its own document).
    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("--ui-test") }
    }

    // Dock-icon click / reopen with no visible windows → show the welcome window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcomeWindow() }
        return true
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
        window.title = "Welcome to OnlyCue"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: Metrics.width, height: Metrics.height))
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
