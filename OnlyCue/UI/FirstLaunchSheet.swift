import SwiftUI

enum FirstLaunchFlag {
    static let key = "didShowFirstLaunchNudge"
}

struct FirstLaunchSheet: View {

    private static let docsURL = URL(string: "https://github.com/chienchuanw/only-cue#documents")

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to OnlyCue")
                .font(.title2.weight(.semibold))
            Text("Drop an audio or video file (or press ⌘O) to start. Press M at the playhead to add a cue. ⌘Z undoes anything.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let docsURL = Self.docsURL {
                Link("Read the docs on GitHub", destination: docsURL)
                    .font(.callout)
            }
            Button("Got it") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 420)
    }
}
