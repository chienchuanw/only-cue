import SwiftUI

/// Decodes the LTC striped onto the active media file's audio (in the
/// background, via `MediaImporter.stripedTimecode`) and publishes the result
/// down the view tree as `EnvironmentValues.stripedTimecode`. `TransportBar`
/// reads it to make the SMPTE readout follow the file's own timecode when there
/// is one. Attached via `.stripedTimecodeReader(item:)` on `DocumentView` —
/// keeps the document body free of the `@State` + async-load plumbing.
private struct StripedTimecodeEnvironmentKey: EnvironmentKey {
    static let defaultValue: StripedTimecodeTrack? = nil
}

extension EnvironmentValues {
    var stripedTimecode: StripedTimecodeTrack? {
        get { self[StripedTimecodeEnvironmentKey.self] }
        set { self[StripedTimecodeEnvironmentKey.self] = newValue }
    }
}

private struct StripedTimecodeHost: ViewModifier {
    let item: MediaItem?
    let document: CueListDocument
    @State private var track: StripedTimecodeTrack?

    func body(content: Content) -> some View {
        content
            .environment(\.stripedTimecode, track)
            .task(id: item?.id) {
                track = nil
                let decoded = await MediaImporter.stripedTimecode(for: item)
                // The scan can outlive its clip: switching from a slow file (LTC
                // late on the last of 8 channels) to one with a cached answer
                // lets the outgoing task finish *after* the incoming one. Without
                // this guard it would publish the old file's timecode under the
                // new file's name — and the readout says `FILE`, asserting the
                // number came off the media on screen.
                guard !Task.isCancelled else { return }
                // Remember the first successful detection so a later flaky scan
                // can fall back to it (#754); write-once via CueCommands.
                if let decoded, let item, item.rememberedLTC == nil {
                    CueCommands.rememberLTC(decoded, forItemID: item.id, document: document)
                }
                track = LTCFallback.resolve(detected: decoded, remembered: item?.rememberedLTC)
            }
    }
}

extension View {
    func stripedTimecodeReader(item: MediaItem?, document: CueListDocument) -> some View {
        modifier(StripedTimecodeHost(item: item, document: document))
    }
}
