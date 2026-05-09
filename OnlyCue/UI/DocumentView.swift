import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {

    @ObservedObject var document: CueListDocument
    @State private var engine = PlayerEngine()
    @State private var showImporter = false
    @State private var pendingAlert: DocumentAlert?
    @State private var seekTask: Task<Void, Never>?
    @State private var showOverlayAppearance = false
    @State private var selectedCueID: Cue.ID?
    @AppStorage(FirstLaunchFlag.key) private var didShowFirstLaunch = false
    @AppStorage(NotesOverlayPreferences.storageKey) private var overlayPrefsData = NotesOverlayPreferences.defaultEncoded
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            ItemListPane(document: document, onDropURLs: importURLs)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            mainPane
                .inspector(isPresented: .constant(true)) {
                    CueListPane(document: document, engine: engine, selection: $selectedCueID)
                        .inspectorColumnWidth(min: 240, ideal: 300, max: 400)
                }
        }
        .navigationSubtitle(document.model.activeItem?.media.displayName ?? "")
        .sheet(isPresented: Binding(
            get: { !didShowFirstLaunch },
            set: { if !$0 { didShowFirstLaunch = true } }
        )) {
            FirstLaunchSheet { didShowFirstLaunch = true }
        }
        .task(id: document.model.activeItemID) { await reloadActive() }
        .resignFirstResponderOnOutsideClick()
        .onReceive(NotificationCenter.default.publisher(for: .editNotesOverlayAppearance)) { _ in
            showOverlayAppearance = true
        }
        .sheet(isPresented: $showOverlayAppearance) {
            NotesOverlayPreferencesSheet(prefs: overlayPrefsBinding)
        }
    }

    private var overlayPrefsBinding: Binding<NotesOverlayPreferences> {
        Binding(
            get: { NotesOverlayPreferences.decode(overlayPrefsData) },
            set: { overlayPrefsData = $0.encoded }
        )
    }

    private var mainPane: some View {
        let activeItem = document.model.activeItem
        return VStack(spacing: 12) {
            Text("OnlyCue")
                .font(.title)
                .accessibilityIdentifier("documentTitle")

            mediaSummary(activeItem)
                .accessibilityIdentifier("mediaSummary")

            PreviewPane(
                document: document,
                engine: engine,
                selectedCueID: selectedCueID,
                onSelectCue: { selectedCueID = $0 }
            )

            Text("\(activeItem?.cues.count ?? 0) cue\((activeItem?.cues.count ?? 0) == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cueCount")

            TransportBar(engine: engine)
                .padding(.top, 4)

            HStack {
                Button("Import Media…") { showImporter = true }
                    .accessibilityIdentifier("importMediaButton")

                Button("Add Cue") { addCueAtPlayhead() }
                    .accessibilityIdentifier("addCueButton")
                    .keyboardShortcut("m", modifiers: [])
                    .disabled(activeItem == nil)
            }

            transportShortcuts
            digitShortcuts
            playheadStepShortcuts

            Text("Drop files on the sidebar or press ⌘O to import.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(minWidth: 560, minHeight: 480)
        .padding()
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: MediaImporter.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handlePickerResult
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            importURLs(urls)
            return true
        }
        .alert(item: $pendingAlert, content: alertContent)
        .onReceive(NotificationCenter.default.publisher(for: .importMediaRequested)) { _ in
            showImporter = true
        }
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

    private func reloadActive() async {
        guard document.model.activeItemID != nil else {
            await engine.unload()
            return
        }
        do {
            try await MediaImporter.loadActive(into: document, engine: engine)
        } catch {
            pendingAlert = .relink(document.model.activeItem?.media.displayName ?? "The media file")
        }
    }

    @ViewBuilder
    private func mediaSummary(_ item: MediaItem?) -> some View {
        if let item {
            Text("\(item.media.displayName) — \(TimeFormat.hms(item.media.duration))")
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
            guard !urls.isEmpty else { return }
            importURLs(urls)
        case .failure(let error):
            pendingAlert = .unsupported(error.localizedDescription)
        }
    }

    private func importURLs(_ urls: [URL]) {
        Task { @MainActor in
            do {
                try await MediaImporter.importMedia(
                    from: urls,
                    into: document,
                    engine: engine,
                    undoManager: undoManager
                )
            } catch let MediaImportError.batch(unsupported) {
                pendingAlert = .unsupported(unsupportedMessage(unsupported))
            } catch {
                pendingAlert = .unsupported(error.localizedDescription)
            }
        }
    }

    private func unsupportedMessage(_ filenames: [String]) -> String {
        let list = filenames.joined(separator: ", ")
        return filenames.count == 1
            ? "\(list) isn't a supported audio or video file."
            : "These files weren't supported and were skipped: \(list)"
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

    private var digitShortcuts: some View {
        ZStack {
            ForEach(0...9, id: \.self) { digit in
                Button("Cue Type \(digit)") { triggerHotkey(digit) }
                    .keyboardShortcut(KeyEquivalent(Character("\(digit)")), modifiers: [])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .disabled(document.model.activeItem == nil)
    }

    private var playheadStepShortcuts: some View {
        ZStack {
            Button("Previous Cue") { stepPlayhead(.previous) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Next Cue") { stepPlayhead(.next) }
                .keyboardShortcut(.downArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .disabled(document.model.activeItem == nil)
    }

    private func triggerHotkey(_ digit: Int) {
        guard let type = document.model.cuePointType(forHotkey: digit) else { return }
        CueCommands.addCueAtPlayhead(
            time: engine.currentTime,
            typeID: type.id,
            document: document,
            undoManager: undoManager
        )
    }

    private func stepPlayhead(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction)
        else { return }
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: target.time) }
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

extension Notification.Name {
    static let importMediaRequested = Notification.Name("OnlyCue.importMediaRequested")
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
