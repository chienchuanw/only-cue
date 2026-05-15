import Foundation

/// Audio-side spectral-flux tempo detection extracted from the inspector
/// extension so the new `CueTempoSheet` can call it without depending on
/// `CueInspectorView`. Behavior is byte-for-byte identical to the previous
/// `CueInspectorView+Tempo.detect` static.
enum CueTempoDetect {

    enum Outcome { case found(TempoEstimate), notDetected, noAudio, failed }

    static func detect(
        bookmark: Data,
        range: ClosedRange<TimeInterval>?,
        beatsPerBar: Int
    ) async -> Outcome {
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
