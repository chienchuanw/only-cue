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
                // `.none` is the user asserting this file carries no LTC, so it
                // has to suppress the *remembered* track too. Clearing it
                // instead would be wrong: the selection is authored and the
                // remembered track is derived, and deselecting "No LTC" must
                // bring the measured answer back (#793).
                let deniesLTC = item?.ltcChannelSelection == LTCChannelSelection.none
                track = LTCFallback.resolve(
                    detected: decoded, remembered: deniesLTC ? nil : item?.rememberedLTC
                )

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
                // Clear / Re-detect do not change the task's id, so they cannot
                // cancel a pass already in flight. Re-read the live item before
                // publishing: if the remembered value is gone or now names a
                // different channel, the user changed their mind while the file
                // was decoding and this result is stale.
                guard document.model.items.first(where: { $0.id == item.id })?
                    .rememberedLTC?.ltcChannel == refined.ltcChannel else { return }
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
