import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    @State private var engine = PlayerEngine()
    @State private var showImporter = false
    @State private var pendingAlert: DocumentAlert?
    @State private var reloadedFor: Data?
    @State private var seekTask: Task<Void, Never>?
    @AppStorage(FirstLaunchFlag.key) private var didShowFirstLaunch = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        mainPane
            .inspector(isPresented: .constant(true)) {
                CueListPane(document: document, engine: engine)
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 400)
            }
            .navigationSubtitle(document.model.media?.displayName ?? "")
            .sheet(isPresented: Binding(
                get: { !didShowFirstLaunch },
                set: { if !$0 { didShowFirstLaunch = true } }
            )) {
                FirstLaunchSheet { didShowFirstLaunch = true }
            }
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
        .alert(item: $pendingAlert, content: alertContent)
        .task(id: document.model.media?.bookmarkData) { await reloadIfNeeded() }
    }

    private func alertContent(_ alert: DocumentAlert) -> Alert {
        switch alert {
        case .unsupported(let message):
            return Alert(
                title: Text("Unsupported file"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        case .relink(let displayName):
            return Alert(
                title: Text("Missing media"),
                message: Text("\(displayName) couldn't be opened from its saved location."),
                primaryButton: .default(Text("Relink media…")) { showImporter = true },
                secondaryButton: .cancel(Text("Continue without media"))
            )
        }
    }

    private func reloadIfNeeded() async {
        guard let bookmark = document.model.media?.bookmarkData else { return }
        guard reloadedFor != bookmark else { return }
        reloadedFor = bookmark
        do {
            try await MediaImporter.reload(into: document, engine: engine)
        } catch {
            pendingAlert = .relink(document.model.media?.displayName ?? "The media file")
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
            pendingAlert = .unsupported(error.localizedDescription)
        }
    }

    private func importURL(_ url: URL) {
        Task { @MainActor in
            do {
                try await MediaImporter.importMedia(from: url, into: document, engine: engine)
            } catch let MediaImportError.unsupportedType(filename) {
                pendingAlert = .unsupported("\(filename) isn't a supported audio or video file.")
            } catch {
                pendingAlert = .unsupported(error.localizedDescription)
            }
        }
    }

    private var transportShortcuts: some View {
        ZStack {
            Button("Play/Pause") { engine.toggle() }
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

    private func jump(by seconds: TimeInterval) {
        let target = max(0, engine.currentTime + seconds)
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target) }
    }

    private func addCueAtPlayhead() {
        CueCommands.addCueAtPlayhead(
            time: engine.currentTime,
            document: document,
            undoManager: undoManager
        )
    }
}

private enum DocumentAlert: Identifiable {
    case unsupported(String)
    case relink(String)

    var id: String {
        switch self {
        case .unsupported(let message): "unsupported:\(message)"
        case .relink(let name): "relink:\(name)"
        }
    }
}
