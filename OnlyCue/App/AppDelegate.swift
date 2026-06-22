import AppKit

/// Thin app delegate for the welcome-window launch flow (#591). Stops macOS
/// from auto-creating a blank untitled document at launch / on reopen, so the
/// `Window("welcome")` scene is what the user sees instead. The app is not
/// sandboxed (ADR-007); `NSDocumentController` recents drive the start page.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}
