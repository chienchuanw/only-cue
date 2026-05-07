import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    @State private var engine = PlayerEngine()
    @State private var showImporter = false
    @State private var importError: ImportAlert?

    var body: some View {
        mainPane
            .inspector(isPresented: .constant(true)) {
                CueListPane(document: document, engine: engine)
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 400)
            }
    }

    private var mainPane: some View {
        VStack(spacing: 12) {
            Text("OnlyCue")
                .font(.title)
                .accessibilityIdentifier("documentTitle")

            mediaSummary
                .accessibilityIdentifier("mediaSummary")

            PreviewPane(engine: engine, media: document.model.media)

            Text("\(document.model.cues.count) cue\(document.model.cues.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cueCount")

            TransportBar(engine: engine)
                .padding(.top, 4)

            HStack {
                Button("Import Media…") { showImporter = true }
                    .accessibilityIdentifier("importMediaButton")
                    .keyboardShortcut("o", modifiers: .command)

                #if DEBUG
                Button("+ Sample cues") { seedSampleCues() }
                    .accessibilityIdentifier("seedSampleCuesButton")
                #endif
            }

            Text("Drop an audio or video file anywhere in this window to import.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(minWidth: 560, minHeight: 480)
        .padding()
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: MediaImporter.allowedContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handlePickerResult
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            importURL(url)
            return true
        }
        .alert(item: $importError) { alert in
            Alert(
                title: Text("Unsupported file"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var mediaSummary: some View {
        if let media = document.model.media {
            Text("\(media.displayName) — \(TimeFormat.hms(media.duration))")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            Text("No media imported")
                .foregroundStyle(.tertiary)
        }
    }

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importURL(url)
        case .failure(let error):
            importError = ImportAlert(message: error.localizedDescription)
        }
    }

    private func importURL(_ url: URL) {
        Task { @MainActor in
            do {
                try await MediaImporter.importMedia(from: url, into: document, engine: engine)
            } catch let MediaImportError.unsupportedType(filename) {
                importError = ImportAlert(
                    message: "\(filename) isn't a supported audio or video file."
                )
            } catch {
                importError = ImportAlert(message: error.localizedDescription)
            }
        }
    }

    #if DEBUG
    private func seedSampleCues() {
        document.model.cues = [
            Cue(id: UUID(), name: "Spot up SR", time: 4.25, colorHex: "#FF6B6B", notes: ""),
            Cue(id: UUID(), name: "Wash full", time: 12.0, colorHex: "#4ECDC4", notes: ""),
            Cue(id: UUID(), name: "Chorus hit", time: 18.5, colorHex: "#FFD93D", notes: "")
        ]
    }
    #endif
}

private struct ImportAlert: Identifiable {
    let id = UUID()
    let message: String
}
