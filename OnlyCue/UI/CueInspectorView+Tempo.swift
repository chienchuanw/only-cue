import SwiftUI

/// Per-cue tempo editing (#246): the inspector's BPM / beats-per-bar fields
/// plus the Detect button that runs `SpectralFluxTempoAnalyzer` on the audio
/// window starting at the cue's time. Split out so `CueInspectorView.swift`
/// stays under the `type_body_length` cap.
extension CueInspectorView {

    func itemID(for cue: Cue) -> MediaItem.ID? {
        document.model.items.first(where: { $0.cues.contains(where: { $0.id == cue.id }) })?.id
    }

    func commitBPM(for cue: Cue) {
        guard let itemID = itemID(for: cue) else { return }
        let trimmed = bpmDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Clearing BPM also clears the meter — a meter without a BPM is
            // orphaned data (DerivedTempoGrid only walks cues with bpm != nil).
            CueCommands.setCueTempo(
                cueID: cue.id,
                bpm: nil,
                beatsPerBar: nil,
                item: itemID,
                document: document,
                undoManager: undoManager
            )
            return
        }
        // Reject NaN / infinity: `Double("nan")` parses to .nan but would
        // propagate into the model and corrupt every grid time downstream.
        guard let value = Double(trimmed), value.isFinite else {
            bpmDraft = cue.bpm.map { String(Int($0.rounded())) } ?? ""
            return
        }
        let meter = cue.beatsPerBar ?? Int(beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        CueCommands.setCueTempo(
            cueID: cue.id,
            bpm: value,
            beatsPerBar: meter,
            item: itemID,
            document: document,
            undoManager: undoManager
        )
    }

    func commitBeatsPerBar(for cue: Cue) {
        guard let itemID = itemID(for: cue) else { return }
        let trimmed = beatsPerBarDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = trimmed.isEmpty ? nil : Int(trimmed)
        CueCommands.setCueTempo(
            cueID: cue.id,
            bpm: cue.bpm,
            beatsPerBar: parsed,
            item: itemID,
            document: document,
            undoManager: undoManager
        )
    }

    func clearTempo(for cue: Cue) {
        guard let itemID = itemID(for: cue) else { return }
        CueCommands.setCueTempo(
            cueID: cue.id,
            bpm: nil,
            beatsPerBar: nil,
            item: itemID,
            document: document,
            undoManager: undoManager
        )
        detectMessage = nil
    }

    func detectTempo(for cue: Cue) {
        guard let item = document.model.items.first(where: { $0.cues.contains(where: { $0.id == cue.id }) }) else { return }
        detectMessage = nil
        detectingCueID = cue.id
        let bookmark = item.media.bookmarkData
        let cueTime = cue.time
        let nextBPMCueTime = item.cues
            .filter { $0.id != cue.id && $0.time > cueTime && $0.bpm != nil }
            .map(\.time)
            .min()
        let detectEnd = min(nextBPMCueTime ?? item.media.duration, cueTime + 30)
        let beatsPerBar = cue.beatsPerBar ?? 4
        let cueID = cue.id
        let itemID = item.id

        Task {
            let outcome = await Self.detect(
                bookmark: bookmark,
                range: cueTime < detectEnd ? cueTime...detectEnd : nil,
                beatsPerBar: beatsPerBar
            )
            await MainActor.run {
                switch outcome {
                case .found(let estimate):
                    CueCommands.setCueTempo(
                        cueID: cueID,
                        bpm: estimate.bpm,
                        beatsPerBar: beatsPerBar,
                        item: itemID,
                        document: document,
                        undoManager: undoManager
                    )
                    detectMessage = estimate.confidence < 0.4
                        ? "Low confidence (\(Int((estimate.confidence * 100).rounded()))%)"
                        : nil
                case .notDetected:
                    detectMessage = "No tempo detected."
                case .noAudio:
                    detectMessage = "This item has no audio to analyze."
                case .failed:
                    detectMessage = "Couldn't open the media file."
                }
                detectingCueID = nil
            }
        }
    }

    enum DetectOutcome { case found(TempoEstimate), notDetected, noAudio, failed }

    static func detect(
        bookmark: Data,
        range: ClosedRange<TimeInterval>?,
        beatsPerBar: Int
    ) async -> DetectOutcome {
        let url: URL
        let didAccess: Bool
        do {
            let resolution = try Bookmarks.resolve(bookmark)
            url = resolution.url
            didAccess = url.startAccessingSecurityScopedResource()
        } catch { return .failed }
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let samples = try await AudioSampleReader.readMonoSamples(from: url, range: range)
            guard let estimate = await SpectralFluxTempoAnalyzer().analyze(
                samples: samples,
                sampleRate: AudioSampleReader.sampleRate,
                beatsPerBar: beatsPerBar,
                bpmHint: nil
            ) else { return .notDetected }
            return .found(estimate)
        } catch AudioSampleReader.Error.noAudioTrack {
            return .noAudio
        } catch {
            return .failed
        }
    }
}
