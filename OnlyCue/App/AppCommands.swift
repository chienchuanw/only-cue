import AppKit
import SwiftUI

struct AppCommands: Commands {

    @AppStorage("showNotesOverlay") private var showNotesOverlay = false
    @AppStorage("showTimelineBreakdown") private var showTimelineBreakdown = false
    @AppStorage("pauseAtEachCue") private var pauseAtEachCue = false

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About OnlyCue") { Self.showAboutPanel() }
        }

        CommandGroup(after: .newItem) {
            Button {
                NotificationCenter.default.post(name: .importMediaRequested, object: nil)
            } label: {
                Label("Import Media…", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .exportCuesToCSVRequested, object: nil)
            } label: {
                Label("Export Cues…", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button {
                Self.newDocumentFromTemplate()
            } label: {
                Label("New from Template…", systemImage: "doc.badge.plus")
            }

            Button {
                NotificationCenter.default.post(name: .saveTemplateRequested, object: nil)
            } label: {
                Label("Save Template As…", systemImage: "square.and.arrow.down.on.square")
            }

            Button {
                NotificationCenter.default.post(name: .loadTemplateRequested, object: nil)
            } label: {
                Label("Load Template…", systemImage: "doc.badge.gearshape")
            }
        }

        CommandGroup(after: .sidebar) {
            Divider()

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

            Divider()

            Toggle("Show Notes Overlay", isOn: $showNotesOverlay)
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Toggle("Show Timeline Breakdown", isOn: $showTimelineBreakdown)
                .keyboardShortcut("b", modifiers: [.command, .shift])

            Toggle("Pause at Each Cue", isOn: $pauseAtEachCue)
                .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button("Snap Selected Cue to Playhead") {
                NotificationCenter.default.post(name: .snapSelectedCueToPlayhead, object: nil)
            }
            .keyboardShortcut("s", modifiers: [])

            Button("Duplicate Cue at Playhead") {
                NotificationCenter.default.post(name: .duplicateSelectedCueAtPlayhead, object: nil)
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Nudge Selected Cue Back") {
                NotificationCenter.default.post(name: .nudgeSelectedCueBack, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .option)

            Button("Nudge Selected Cue Forward") {
                NotificationCenter.default.post(name: .nudgeSelectedCueForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .option)
        }

        CommandMenu("Tools") {
            Button("Edit Note Overlay Appearance…") {
                NotificationCenter.default.post(name: .editNotesOverlayAppearance, object: nil)
            }

            Divider()

            Button("OSC Monitor…") {
                NotificationCenter.default.post(name: .oscMonitorRequested, object: nil)
            }
        }
    }

    private static func newDocumentFromTemplate() {
        do {
            try TemplateAction.newDocument()
        } catch {
            // Corrupt / unreadable template file picked in the open panel —
            // surface it; nothing was created.
            _ = NSApplication.shared.presentError(error)
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
