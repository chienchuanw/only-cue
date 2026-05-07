import SwiftUI

struct DocumentView: View {
    @ObservedObject var document: CueListDocument

    var body: some View {
        VStack(spacing: 12) {
            Text("OnlyCue")
                .font(.title)
            Text("\(document.model.cues.count) cue\(document.model.cues.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Text("Drop a media file or press ⌘O. Preview, waveform, and cue list arrive in later epics.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(minWidth: 480, minHeight: 320)
        .padding()
    }
}
