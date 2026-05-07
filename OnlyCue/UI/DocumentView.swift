import SwiftUI

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    @State private var engine = PlayerEngine()

    var body: some View {
        VStack(spacing: 12) {
            Text("OnlyCue")
                .font(.title)
                .accessibilityIdentifier("documentTitle")
            Text("\(document.model.cues.count) cue\(document.model.cues.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cueCount")

            TransportBar(engine: engine)
                .padding(.top, 4)

            Text("Empty document. Preview, waveform, and cue list arrive in later epics.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(minWidth: 480, minHeight: 320)
        .padding()
    }
}
