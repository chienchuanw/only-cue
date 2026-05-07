import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About OnlyCue") { Self.showAboutPanel() }
        }
    }

    private static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "A native macOS cue list editor for lighting designers and show programmers.\n\nInspired by CuePoints (cuepoints.com).",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
