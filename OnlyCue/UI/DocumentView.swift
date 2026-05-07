import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    @State private var engine = PlayerEngine()
    @State private var showImporter = false
    @State private var importError: ImportAlert?

    var body: some View {
        VStack(spacing: 12) {
            Text("OnlyCue")
                .font(.title)
                .accessibilityIdentifier("documentTitle")

            mediaSummary
                .accessibilityIdentifier("mediaSummary")

            Text("\(document.model.cues.count) cue\(document.model.cues.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cueCount")

            TransportBar(engine: engine)
                .padding(.top, 4)

            Button("Import Media…") { showImporter = true }
                .accessibilityIdentifier("importMediaButton")
                .keyboardShortcut("o", modifiers: .command)

            Text("Drop an audio or video file anywhere in this window to import.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(minWidth: 480, minHeight: 320)
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
}

private struct ImportAlert: Identifiable {
    let id = UUID()
    let message: String
}
