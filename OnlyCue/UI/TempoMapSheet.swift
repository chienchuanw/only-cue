import SwiftUI

/// Document-scoped editor for the active media item's tempo map (epic #199): a
/// table of constant-tempo sections (start, BPM, beats-per-bar, downbeat offset)
/// with add / split-at-playhead / delete, a per-section "Detect tempo" (DSP), and
/// a one-shot "Detect tempo for whole item". Reached via `Tools → Tempo Map…`.
/// All edits route through `CueCommands+Tempo` (undoable). The grid the sections
/// describe renders on the waveform via `View → Show Tempo Grid`.
struct TempoMapSheet: View {

    @ObservedObject var document: CueListDocument
    let engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) var undoManager

    @State private var detectingSectionID: TempoSection.ID?
    @State private var detectMessages: [TempoSection.ID: String] = [:]
    @State private var detectingWholeItem = false
    @State private var wholeItemMessage: String?

    private var activeItem: MediaItem? { document.model.activeItem }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tempo Map").font(.headline)
            Divider()
            if let item = activeItem {
                header(item: item)
                Divider()
                sectionTable(item: item)
                Divider()
                footer(item: item)
            } else {
                Text("Open or select a media item to edit its tempo map.")
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 540)
        .accessibilityIdentifier("tempoMapSheet")
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(item: MediaItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.media.displayName).font(.subheadline).bold()
                Text(String(format: "%.1f s", item.media.duration)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                detectWholeItem(item: item)
            } label: {
                if detectingWholeItem {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Detect tempo for whole item")
                }
            }
            .disabled(detectingWholeItem)
        }
        if let wholeItemMessage {
            Text(wholeItemMessage).font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func sectionTable(item: MediaItem) -> some View {
        if item.tempoMap.sections.isEmpty {
            Text("No tempo grid yet. Add a section at the playhead, or detect the tempo.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.tempoMap.sections) { section in
                        sectionRow(section, in: item)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    @ViewBuilder
    private func sectionRow(_ section: TempoSection, in item: MediaItem) -> some View {
        let isFirst = section.id == item.tempoMap.sections.first?.id
        HStack(spacing: 8) {
            field("Start", binding(\.startSeconds, of: section, in: item) { $0.startSeconds = max(0, $1) }, suffix: "s")
                .disabled(isFirst)
            field("BPM", binding(\.bpm, of: section, in: item) { $0.bpm = $1 }, suffix: "BPM")
            Stepper(value: beatsPerBarBinding(section, in: item), in: 1...16) { Text("\(section.beatsPerBar)/bar") }
                .fixedSize()
            field(
                "Offset",
                binding(\.downbeatOffsetSeconds, of: section, in: item) { $0.downbeatOffsetSeconds = max(0, $1) },
                suffix: "dbeat"
            )
            Spacer()
            Button {
                detectSection(section, in: item)
            } label: {
                if detectingSectionID == section.id { ProgressView().controlSize(.small) } else { Image(systemName: "wand.and.stars") }
            }
            .disabled(detectingSectionID != nil)
            .help("Detect this section's tempo")
            Button(role: .destructive) {
                CueCommands.removeTempoSection(section.id, item: item.id, document: document, undoManager: undoManager)
                detectMessages[section.id] = nil
            } label: { Image(systemName: "trash") }
            .disabled(item.tempoMap.sections.count == 1)
        }
        .accessibilityIdentifier("tempoSectionRow")
        if let message = detectMessages[section.id] {
            Text(message).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func footer(item: MediaItem) -> some View {
        HStack {
            Button("Add Section at Playhead") {
                CueCommands.addTempoSection(atSeconds: engine.currentTime, item: item.id, document: document, undoManager: undoManager)
            }
            Button("Split Section at Playhead") {
                CueCommands.splitTempoSection(atSeconds: engine.currentTime, item: item.id, document: document, undoManager: undoManager)
            }
            Spacer()
            Button(role: .destructive) {
                CueCommands.clearTempoMap(item: item.id, document: document, undoManager: undoManager)
                detectMessages = [:]
            } label: { Text("Clear Tempo Map") }
            .disabled(item.tempoMap.sections.isEmpty)
        }
    }

    // MARK: - Detection

    private enum DetectOutcome { case found(TempoEstimate), notDetected, noAudio, failed }

    private func detectSection(_ section: TempoSection, in item: MediaItem) {
        detectMessages[section.id] = nil
        detectingSectionID = section.id
        let start = section.startSeconds
        let end = item.tempoMap.sectionEndSeconds(for: section, itemDuration: item.media.duration)
        let beatsPerBar = section.beatsPerBar
        let bookmark = item.media.bookmarkData
        let itemID = item.id
        Task {
            let outcome = await Self.detect(bookmark: bookmark, range: start < end ? start...end : nil, beatsPerBar: beatsPerBar)
            await MainActor.run {
                apply(outcome, toSection: section.id, itemID: itemID)
                detectingSectionID = nil
            }
        }
    }

    private func detectWholeItem(item: MediaItem) {
        wholeItemMessage = nil
        detectingWholeItem = true
        let bookmark = item.media.bookmarkData
        let itemID = item.id
        Task {
            let outcome = await Self.detect(bookmark: bookmark, range: nil, beatsPerBar: TempoSection.defaultBeatsPerBar)
            await MainActor.run {
                switch outcome {
                case .found(let estimate):
                    CueCommands.setTempoMap(
                        TempoMap.singleSection(
                            bpm: estimate.bpm,
                            beatsPerBar: TempoSection.defaultBeatsPerBar,
                            downbeatOffsetSeconds: estimate.downbeatOffsetSeconds
                        ),
                        item: itemID,
                        document: document,
                        undoManager: undoManager
                    )
                    wholeItemMessage = lowConfidenceMessage(estimate)
                case .notDetected: wholeItemMessage = "No tempo detected."
                case .noAudio: wholeItemMessage = "This item has no audio to analyze."
                case .failed: wholeItemMessage = "Couldn't open the media file."
                }
                detectingWholeItem = false
            }
        }
    }

    private func apply(_ outcome: DetectOutcome, toSection id: TempoSection.ID, itemID: MediaItem.ID) {
        switch outcome {
        case .found(let estimate):
            CueCommands.updateTempoSection(
                id,
                bpm: estimate.bpm,
                downbeatOffsetSeconds: estimate.downbeatOffsetSeconds,
                item: itemID,
                document: document,
                undoManager: undoManager
            )
            detectMessages[id] = lowConfidenceMessage(estimate)
        case .notDetected: detectMessages[id] = "No tempo detected."
        case .noAudio: detectMessages[id] = "This item has no audio to analyze."
        case .failed: detectMessages[id] = "Couldn't open the media file."
        }
    }

    private func lowConfidenceMessage(_ estimate: TempoEstimate) -> String? {
        estimate.confidence < 0.4 ? "Low confidence (\(Int((estimate.confidence * 100).rounded()))%)" : nil
    }

    /// Resolve the bookmark, read the audio span (`range` or the whole track), and run
    /// the DSP analyzer. Runs off the main actor.
    private static func detect(bookmark: Data, range: ClosedRange<TimeInterval>?, beatsPerBar: Int) async -> DetectOutcome {
        let url: URL
        let didAccess: Bool
        do {
            let resolution = try Bookmarks.resolve(bookmark)
            url = resolution.url
            didAccess = url.startAccessingSecurityScopedResource()
        } catch {
            return .failed
        }
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let samples = try await AudioSampleReader.readMonoSamples(from: url, range: range)
            guard let estimate = await SpectralFluxTempoAnalyzer().analyze(
                samples: samples, sampleRate: AudioSampleReader.sampleRate, beatsPerBar: beatsPerBar, bpmHint: nil
            ) else {
                return .notDetected
            }
            return .found(estimate)
        } catch AudioSampleReader.Error.noAudioTrack {
            return .noAudio
        } catch {
            return .failed
        }
    }
}

/// Hosts the Tempo Map sheet on a view: presents it when `Tools → Tempo Map…`
/// posts `.tempoMapRequested`, and handles `Tools → Split Tempo Section at
/// Playhead` (`.splitTempoSectionAtPlayhead`). Mirrors the
/// `.timecodeSettingsSheet(...)` host-modifier pattern.
private struct TempoMapSheetHost: ViewModifier {
    let document: CueListDocument
    let engine: PlayerEngine
    @Environment(\.undoManager) private var undoManager
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .tempoMapRequested)) { _ in
                isPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .splitTempoSectionAtPlayhead)) { _ in
                guard let itemID = document.model.activeItemID else { return }
                CueCommands.splitTempoSection(atSeconds: engine.currentTime, item: itemID, document: document, undoManager: undoManager)
            }
            .sheet(isPresented: $isPresented) {
                TempoMapSheet(document: document, engine: engine)
            }
    }
}

extension View {
    func tempoMapSheet(document: CueListDocument, engine: PlayerEngine) -> some View {
        modifier(TempoMapSheetHost(document: document, engine: engine))
    }
}
