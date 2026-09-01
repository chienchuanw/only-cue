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
                guard !Task.isCancelled else { return }
                if let decoded, let item, item.rememberedLTC == nil {
                    CueCommands.rememberLTC(decoded, forItemID: item.id, document: document)
                }
                track = LTCFallback.resolve(detected: decoded, remembered: item?.rememberedLTC)

                // Phase 2 (#793): the windowed scan can bound only the start. Now that
                // the channel is known, measure the real extent across the whole file
                // in the background and upgrade the readout in place. Skipped when the
                // pass has already run (validUntil is set) and when the user named the
                // channel, because MediaImporter went straight to the full-file pass
                // in that case and the bounds are already measured.
                guard let item, item.ltcChannelSelection == .auto,
                      let phase1 = track, phase1.validUntil == nil else { return }
                let refined = await MediaImporter.fullFileStripedTimecode(
                    for: item, channel: phase1.ltcChannel
                )
                guard !Task.isCancelled, let refined else { return }
                StripedTimecodeCache.shared.store(refined, for: item.id)
                CueCommands.refineRememberedLTC(refined, forItemID: item.id, document: document)
                track = refined
            }
    }
}

extension View {
    func stripedTimecodeReader(item: MediaItem?, document: CueListDocument) -> some View {
        modifier(StripedTimecodeHost(item: item, document: document))
    }
}
