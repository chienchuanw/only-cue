import SwiftUI

struct CueListPane: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine

    @State private var selection: Cue.ID?

    var body: some View {
        Group {
            if document.model.cues.isEmpty {
                emptyState
            } else {
                cueList
            }
        }
        .frame(minWidth: 240)
        .accessibilityIdentifier("cueListPane")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No cues yet")
                .font(.headline)
            Text("Press M to add one at the playhead")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("cueListEmptyState")
    }

    private var cueList: some View {
        List(selection: $selection) {
            ForEach(Array(document.model.cues.enumerated()), id: \.element.id) { index, cue in
                CueRowView(index: index + 1, cue: cue)
                    .tag(cue.id)
            }
        }
        .onChange(of: selection) { _, newValue in
            guard
                let id = newValue,
                let cue = document.model.cues.first(where: { $0.id == id })
            else { return }
            Task { await engine.seek(to: cue.time) }
        }
    }
}
