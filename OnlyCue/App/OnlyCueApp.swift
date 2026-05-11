import SwiftUI

@main
struct OnlyCueApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: CueListDocument.init) { file in
            DocumentView(document: file.document)
        }
        .commands { AppCommands() }

        Settings {
            OSCSettingsView()
        }
    }
}
