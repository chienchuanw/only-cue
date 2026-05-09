import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About OnlyCue") { Self.showAboutPanel() }
        }

        CommandMenu("View") {
            Button("Zoom In") {
                NotificationCenter.default.post(name: .waveformZoomIn, object: nil)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .waveformZoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                NotificationCenter.default.post(name: .waveformZoomReset, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Zoom In Vertically") {
                NotificationCenter.default.post(name: .waveformVerticalZoomIn, object: nil)
            }
            .keyboardShortcut("=", modifiers: [.command, .option])

            Button("Zoom Out Vertically") {
                NotificationCenter.default.post(name: .waveformVerticalZoomOut, object: nil)
            }
            .keyboardShortcut("-", modifiers: [.command, .option])

            Button("Actual Vertical Size") {
                NotificationCenter.default.post(name: .waveformVerticalZoomReset, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
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
