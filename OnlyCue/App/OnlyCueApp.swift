import SwiftUI

@main
struct OnlyCueApp: App {

    #if DEBUG
    init() {
        Task { @MainActor in
            UITestSeedHandler.openSeededDocumentIfRequested()
        }
    }
    #endif

    var body: some Scene {
        DocumentGroup(newDocument: CueListDocument.init) { file in
            DocumentView(document: file.document)
        }
        .commands { AppCommands() }

        Settings {
            TabView {
                OSCSettingsView()
                    .tabItem { Label("OSC", systemImage: "dot.radiowaves.left.and.right") }
                KeyboardSettingsView()
                    .tabItem { Label("Keyboard", systemImage: "keyboard") }
                AudioSettingsView()
                    .tabItem { Label("Audio", systemImage: "hifispeaker") }
            }
        }
    }
}
