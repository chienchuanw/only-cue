import AppKit
import SwiftUI

struct AppCommands: Commands {

    @AppStorage("showNotesOverlay") private var showNotesOverlay = false
    @AppStorage("showTimelineBreakdown") private var showTimelineBreakdown = false
    @AppStorage("showTempoGrid") private var showTempoGrid = false
    @AppStorage("pauseAtEachCue") private var pauseAtEachCue = false
    @ObservedObject private var keymapStore = KeymapStore.shared

    private func shortcut(_ action: KeymapAction) -> KeyboardShortcut {
        keymapStore.keymap.chord(for: action).keyboardShortcut
            ?? Keymap.default.chord(for: action).keyboardShortcut
            ?? KeyboardShortcut(KeyEquivalent("/"), modifiers: .command)
    }

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
            .keyboardShortcut(shortcut(.importMedia))

            Button {
                NotificationCenter.default.post(name: .exportCuesToCSVRequested, object: nil)
            } label: {
                Label("Export Cues…", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut(shortcut(.exportCues))

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
            .keyboardShortcut(shortcut(.waveformZoomIn))

            Button("Zoom Out") {
                NotificationCenter.default.post(name: .waveformZoomOut, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomOut))

            Button("Actual Size") {
                NotificationCenter.default.post(name: .waveformZoomReset, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomReset))

            Divider()

            Button("Zoom In Vertically") {
                NotificationCenter.default.post(name: .waveformVerticalZoomIn, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformVerticalZoomIn))

            Button("Zoom Out Vertically") {
                NotificationCenter.default.post(name: .waveformVerticalZoomOut, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformVerticalZoomOut))

            Button("Actual Vertical Size") {
                NotificationCenter.default.post(name: .waveformVerticalZoomReset, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformVerticalZoomReset))

            Divider()

            Toggle("Show Notes Overlay", isOn: $showNotesOverlay)
                .keyboardShortcut(shortcut(.toggleNotesOverlay))

            Toggle("Show Timeline Breakdown", isOn: $showTimelineBreakdown)
                .keyboardShortcut(shortcut(.toggleTimelineBreakdown))

            Toggle("Show Tempo Grid", isOn: $showTempoGrid)
                .keyboardShortcut(shortcut(.toggleTempoGrid))

            Toggle("Pause at Each Cue", isOn: $pauseAtEachCue)
                .keyboardShortcut(shortcut(.togglePauseAtEachCue))

            Divider()

            Button("Snap Selected Cue to Playhead") {
                NotificationCenter.default.post(name: .snapSelectedCueToPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCueToPlayhead))

            Button("Snap Selected Cues to Nearest Beat") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBeat, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBeat))

            Button("Snap Selected Cues to Nearest Bar") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBar, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBar))

            Button("Duplicate Cue at Playhead") {
                NotificationCenter.default.post(name: .duplicateSelectedCueAtPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.duplicateCueAtPlayhead))

            Button("Nudge Selected Cue Back") {
                NotificationCenter.default.post(name: .nudgeSelectedCueBack, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueBack))

            Button("Nudge Selected Cue Forward") {
                NotificationCenter.default.post(name: .nudgeSelectedCueForward, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueForward))
        }

        CommandMenu("Playback") {
            Button("Speed Up") {
                NotificationCenter.default.post(name: .playbackRateUp, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateUp))
            .accessibilityIdentifier("playbackRateUpMenuItem")

            Button("Slow Down") {
                NotificationCenter.default.post(name: .playbackRateDown, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateDown))
            .accessibilityIdentifier("playbackRateDownMenuItem")

            Button("Reset Speed") {
                NotificationCenter.default.post(name: .playbackRateReset, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateReset))
            .accessibilityIdentifier("playbackRateResetMenuItem")
        }

        CommandMenu("Tools") {
            Button("Manage Types…") {
                NotificationCenter.default.post(name: .manageTypesRequested, object: nil)
            }
            .accessibilityIdentifier("manageTypesButton")

            Divider()

            Button("Edit Note Overlay Appearance…") {
                NotificationCenter.default.post(name: .editNotesOverlayAppearance, object: nil)
            }

            Divider()

            Button("OSC Monitor…") {
                NotificationCenter.default.post(name: .oscMonitorRequested, object: nil)
            }

            Button("Timecode Settings…") {
                NotificationCenter.default.post(name: .timecodeSettingsRequested, object: nil)
            }

            // Tempo Map / Split / Add-Cues-on-Beat-or-Bar menu items removed in v11
            // transition (#244). The Tempo Map sheet, its notifications, the related
            // KeymapAction cases, and the underlying commands get deleted in #248.
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
