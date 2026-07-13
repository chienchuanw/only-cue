import SwiftUI

@main
struct OnlyCueApp: App {

    // Suppresses the default auto-untitled document at launch so the welcome
    // window is what the user sees (#591).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Task { @MainActor in
            // Dark-only main window (ADR-029): pin system chrome to Dark Aqua
            // regardless of the host's appearance setting.
            AppAppearance.applyDarkOnly()
            #if DEBUG
            // Test hooks run after the dark-only pin so a `--ui-test-appearance`
            // override (e.g. the Light visual baseline) can still take effect.
            // The defaults reset runs first so the handlers below re-establish
            // their deterministic state on a clean persistent domain (#603).
            UITestDefaultsResetHandler.applyIfRequested()
            UITestAppearanceHandler.applyAppearanceOverrideIfRequested()
            UITestFirstLaunchHandler.applyFirstLaunchOverrideIfRequested()
            UITestLTCHandler.applyIfRequested()
            // Register the window-frame pin BEFORE opening the seed document so
            // the didBecomeKey observer is live when the window appears (#614).
            UITestWindowFrameHandler.applyIfRequested()
            UITestSeedHandler.openSeededDocumentIfRequested()
            #endif
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: CueListDocument.init) { file in
            DocumentView(document: file.document)
                .tint(DS.Color.cueIndigo)
        }
        // Open at the Figma design size (1280×812 frame): sidebar 240 + preview
        // 680 + cue-list inspector 360 = 1280, so all three panes fit. Users can
        // still resize.
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands() }

        // The start page (#591) is an AppKit window owned by `AppDelegate`
        // (`StartView` in an NSHostingController), because a SwiftUI `Window`
        // scene doesn't reliably auto-open at launch inside a DocumentGroup app
        // on macOS 14. Reopen via File → Welcome to OnlyCue.

        Settings {
            // Canonical Settings-tab order per the figma↔app audit (§1.1):
            // Audio → Keyboard → OSC, declared left-to-right. Timecode
            // remains a document-scoped sheet (Tools → Timecode Settings…)
            // because its bindings target `document.model.timecodeSettings`;
            // promoting it to an app-scoped Settings tab requires a separate
            // architecture pass (#394's structural arm). The custom dark
            // pill toolbar style (§1.2, §1.3) is similarly deferred until
            // the NSToolbarDelegate work lands.
            TabView {
                AudioSettingsView()
                    .tabItem { Label("Audio", systemImage: "hifispeaker") }
                KeyboardSettingsView()
                    .tabItem { Label("Keyboard", systemImage: "keyboard") }
                OSCSettingsView()
                    .tabItem { Label("OSC", systemImage: "dot.radiowaves.left.and.right") }
            }
            .tint(DS.Color.cueIndigo)
        }
    }
}
