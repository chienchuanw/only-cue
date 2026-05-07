import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    @State private var engine = PlayerEngine()
    @State private var showImporter = false
    @State private var importError: ImportAlert?
    @State private var relinkPrompt: RelinkPrompt?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        mainPane
            .inspector(isPresented: .constant(true)) {
                CueListPane(document: document, engine: engine)
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 400)
            }
            .navigationSubtitle(document.model.media?.displayName ?? "")
    }

    private var mainPane: some View {
        VStack(spacing: 12) {
            Text("OnlyCue")
                .font(.title)
                .accessibilityIdentifier("documentTitle")

            mediaSummary
                .accessibilityIdentifier("mediaSummary")

            PreviewPane(document: document, engine: engine)

            Text("\(document.model.cues.count) cue\(document.model.cues.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cueCount")

            TransportBar(engine: engine)
                .padding(.top, 4)

            HStack {
                Button("Import Media…") { showImporter = true }
                    .accessibilityIdentifier("importMediaButton")
                    .keyboardShortcut("o", modifiers: .command)

                Button("Add Cue") { addCueAtPlayhead() }
                    .accessibilityIdentifier("addCueButton")
                    .keyboardShortcut("m", modifiers: [])
            }

            transportShortcuts

            Text("Drop a file here or press ⌘O to import.")
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
        .alert(item: $relinkPrompt) { prompt in
            Alert(
                title: Text("Missing media"),
                message: Text("\(prompt.displayName) couldn't be opened from its saved location."),
                primaryButton: .default(Text("Relink media…")) { showImporter = true },
                secondaryButton: .cancel(Text("Continue without media"))
            )
        }
        .task(id: document.model.media?.bookmarkData) { await reloadIfNeeded() }
    }

    private func reloadIfNeeded() async {
        guard document.model.media != nil, engine.player.currentItem == nil else { return }
        do {
            try await MediaImporter.reload(into: document, engine: engine)
        } catch {
            relinkPrompt = RelinkPrompt(
                displayName: document.model.media?.displayName ?? "The media file"
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

    private var transportShortcuts: some View {
        ZStack {
            Button("Play/Pause") { togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Back 1s") { jump(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward 1s") { jump(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func togglePlayPause() {
        if engine.rate > 0 { engine.pause() } else { engine.play() }
    }

    private func jump(by seconds: TimeInterval) {
        Task { await engine.seek(to: max(0, engine.currentTime + seconds)) }
    }

    private func addCueAtPlayhead() {
        CueCommands.addCueAtPlayhead(
            time: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }
}

private struct ImportAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct RelinkPrompt: Identifiable {
    let id = UUID()
    let displayName: String
}
