import AppKit
import SwiftUI

struct AppCommands: Commands {

    @AppStorage("showNotesOverlay") private var showNotesOverlay = false
    @AppStorage("showTimelineBreakdown") private var showTimelineBreakdown = false
    @AppStorage("showTempoGrid") private var showTempoGrid = false
    @AppStorage("showLyricsOverlay") private var showLyricsOverlay = false
    @AppStorage("pauseAtEachCue") private var pauseAtEachCue = false
    @AppStorage("autoScrollWaveform") private var autoScrollWaveform = true
    @ObservedObject private var keymapStore = KeymapStore.shared
    @ObservedObject private var ltcRoutingStore = LTCRoutingStore.shared
    @FocusedValue(\.currentPlaybackMode) private var currentPlaybackMode

    private func shortcut(_ action: KeymapAction) -> KeyboardShortcut {
        keymapStore.keymap.chord(for: action).keyboardShortcut
            ?? Keymap.default.chord(for: action).keyboardShortcut
            ?? KeyboardShortcut(KeyEquivalent("/"), modifiers: .command)
    }

    /// Renders one Playback Mode menu item with a leading checkmark when this
    /// mode is the active document's current selection. The macOS SwiftUI
    /// renderer maps `Image(systemName: "checkmark")` leading a `Label` to the
    /// underlying `NSMenuItem.state`, which XCUITest reads as `value == "1"`.
    @ViewBuilder
    private func playbackModeItem(_ mode: PlaybackMode, title: String, id: String) -> some View {
        let isActive = (currentPlaybackMode ?? .playOnce) == mode
        Button {
            NotificationCenter.default.post(name: .setPlaybackModeRequested, object: mode)
        } label: {
            if isActive {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .accessibilityIdentifier(id)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About OnlyCue") { Self.showAboutPanel() }
            Divider()
            // App-global, stateless — call the presenter directly (#565).
            Button("Check for Updates…") {
                Task { await UpdateCheckPresenter.shared.run() }
            }
            .accessibilityIdentifier("checkForUpdatesMenuItem")
        }

        // Document *creation* belongs beside New, above Open… — it is a New
        // verb, unlike the import/export block below (#707).
        CommandGroup(after: .newItem) {
            Button {
                Self.newDocumentFromTemplate()
            } label: {
                Label("New from Template…", systemImage: "doc.badge.plus")
            }
        }

        // Everything else OnlyCue adds sits *below* the standard document block
        // (Save, Save As…, Duplicate, Rename…, Move To…, Revert To). Injecting
        // it after `.newItem` instead buried those nine standard items at the
        // bottom of a 24-item menu, and users concluded the app had no Save As
        // at all (#707). Order follows the macOS HIG: app-specific file
        // operations come after the standard ones.
        //
        // AppKit's own `Share` item lands between `Revert To` and this block,
        // and no SwiftUI placement sits between those two. `before: .printItem`
        // resolves to the same spot but emits a doubled separator, so
        // `.saveItem` is the better of the two available anchors.
        CommandGroup(after: .saveItem) {
            Divider()

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

            Button {
                NotificationCenter.default.post(name: .exportBundleRequested, object: nil)
            } label: {
                Label("Export Bundle…", systemImage: "shippingbox")
            }
            .accessibilityIdentifier("exportBundleMenuItem")

            Button {
                NotificationCenter.default.post(name: .exportPotPlayerRequested, object: nil)
            } label: {
                Label("Export PotPlayer Bookmarks…", systemImage: "bookmark")
            }
            .accessibilityIdentifier("exportPotPlayerMenuItem")

            Button {
                NotificationCenter.default.post(name: .sendToMA2Requested, object: nil)
            } label: {
                Label("Send to grandMA2…", systemImage: "network")
            }
            .accessibilityIdentifier("sendToMA2MenuItem")

            Button {
                NotificationCenter.default.post(name: .exportMA2PluginRequested, object: nil)
            } label: {
                Label("Export grandMA2 plugin…", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("exportMA2PluginMenuItem")

            Divider()

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

            Button("Zoom In Horizontally") {
                NotificationCenter.default.post(name: .waveformZoomIn, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomIn))

            Button("Zoom Out Horizontally") {
                NotificationCenter.default.post(name: .waveformZoomOut, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomOut))

            Button("Actual Horizontal Size") {
                NotificationCenter.default.post(name: .waveformZoomReset, object: nil)
            }
            .keyboardShortcut(shortcut(.waveformZoomReset))

            Divider()

            Button("Cue Mode") {
                NotificationCenter.default.post(name: .editorModeChangeRequested, object: EditorMode.cue)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Lyric Mode") {
                NotificationCenter.default.post(name: .editorModeChangeRequested, object: EditorMode.lyric)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Show Mode") {
                NotificationCenter.default.post(name: .editorModeChangeRequested, object: EditorMode.show)
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button(showNotesOverlay ? "Hide Notes Overlay" : "Show Notes Overlay") {
                showNotesOverlay.toggle()
            }
            .keyboardShortcut(shortcut(.toggleNotesOverlay))

            Button(showLyricsOverlay ? "Hide Lyrics Overlay" : "Show Lyrics Overlay") {
                showLyricsOverlay.toggle()
            }
            .accessibilityIdentifier("toggleLyricsOverlayMenuItem")

            Button(showTimelineBreakdown ? "Hide Timeline Breakdown" : "Show Timeline Breakdown") {
                showTimelineBreakdown.toggle()
            }
            .keyboardShortcut(shortcut(.toggleTimelineBreakdown))

            Button(showTempoGrid ? "Hide Tempo Grid" : "Show Tempo Grid") {
                showTempoGrid.toggle()
            }
            .keyboardShortcut(shortcut(.toggleTempoGrid))

            Divider()

            // Persistent behavior toggle (#532): a leading checkmark when on,
            // mirroring the Playback-mode items, rather than a Show/Hide
            // verb-flip — the macOS-standard affordance for an on/off setting.
            // Note: the checkmark (and a SwiftUI Toggle's state) is NOT exposed
            // to XCUITest — neither `value` nor `isSelected` reflects it — so the
            // menu UI test only smoke-checks presence/clickability; the flip and
            // gating are unit-tested in `WaveformZoomControllerTests`.
            Button {
                autoScrollWaveform.toggle()
            } label: {
                if autoScrollWaveform {
                    Label("Auto-Scroll Waveform", systemImage: "checkmark")
                } else {
                    Text("Auto-Scroll Waveform")
                }
            }
            .accessibilityIdentifier("toggleAutoScrollWaveformMenuItem")
        }

        CommandMenu("Cue") {
            Button("Duplicate at Playhead") {
                NotificationCenter.default.post(name: .duplicateSelectedCueAtPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.duplicateCueAtPlayhead))

            Button("Nudge Back") {
                NotificationCenter.default.post(name: .nudgeSelectedCueBack, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueBack))

            Button("Nudge Forward") {
                NotificationCenter.default.post(name: .nudgeSelectedCueForward, object: nil)
            }
            .keyboardShortcut(shortcut(.nudgeSelectedCueForward))

            Divider()

            Button("Snap to Playhead") {
                NotificationCenter.default.post(name: .snapSelectedCueToPlayhead, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCueToPlayhead))

            Button("Snap to Nearest Beat") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBeat, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBeat))

            Button("Snap to Nearest Bar") {
                NotificationCenter.default.post(name: .snapSelectedCuesToBar, object: nil)
            }
            .keyboardShortcut(shortcut(.snapSelectedCuesToBar))

            Divider()

            Button {
                NotificationCenter.default.post(name: .exportCueListRequested, object: nil)
            } label: {
                Label("Export Cue List…", systemImage: "square.and.arrow.up.on.square")
            }
            .accessibilityIdentifier("exportCueListMenuItem")

            Button {
                NotificationCenter.default.post(name: .importCueListRequested, object: nil)
            } label: {
                Label("Import Cue List…", systemImage: "square.and.arrow.down.on.square")
            }
            .accessibilityIdentifier("importCueListMenuItem")
        }

        CommandMenu("Playback") {
            // Spec §3.5: disable the speed items while LTC output is active —
            // any change would be rejected by the interlock anyway. The
            // keyboard shortcuts in `PlaybackRateShortcuts` still fire the
            // interlock beep/flash if used.
            let ltcOn = ltcRoutingStore.settings.isEnabled

            Button("Speed Up") {
                NotificationCenter.default.post(name: .playbackRateUp, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateUp))
            .accessibilityIdentifier("playbackRateUpMenuItem")
            .disabled(ltcOn)

            Button("Slow Down") {
                NotificationCenter.default.post(name: .playbackRateDown, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateDown))
            .accessibilityIdentifier("playbackRateDownMenuItem")
            .disabled(ltcOn)

            Button("Reset Speed") {
                NotificationCenter.default.post(name: .playbackRateReset, object: nil)
            }
            .keyboardShortcut(shortcut(.playbackRateReset))
            .accessibilityIdentifier("playbackRateResetMenuItem")
            .disabled(ltcOn)

            Divider()

            playbackModeItem(.playOnce, title: "Play Once", id: "playbackModePlayOnceMenuItem")
            playbackModeItem(.loop, title: "Loop Current Media", id: "playbackModeLoopMenuItem")
            playbackModeItem(.autoNext, title: "Auto Play Next Media", id: "playbackModeAutoNextMenuItem")

            Divider()

            Button(pauseAtEachCue ? "Don't Pause at Each Cue" : "Pause at Each Cue") {
                pauseAtEachCue.toggle()
            }
            .keyboardShortcut(shortcut(.togglePauseAtEachCue))
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

}

// Static helpers live in an extension so they don't count toward the struct's
// SwiftLint `type_body_length` budget — same "extract at the cap" pattern the
// codebase uses elsewhere (e.g. OSCServerHost / ExportSheetPresenter).
private extension AppCommands {

    static func newDocumentFromTemplate() {
        do {
            try TemplateAction.newDocument()
        } catch {
            // Corrupt / unreadable template file picked in the open panel —
            // surface it; nothing was created.
            _ = NSApplication.shared.presentError(error)
        }
    }

    static func showAboutPanel() {
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
