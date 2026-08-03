import SwiftUI

extension DocumentView {

    /// The per-clip LTC strip, shown in the main pane only when LTC routing is
    /// enabled and a media item is active (per-media LTC, epic #231). In an
    /// extension to keep the `DocumentView` body within the type-length limit.
    @ViewBuilder
    func ltcStripIfEnabled(_ activeItem: MediaItem?) -> some View {
        if let activeItem, ltcRoutingStore.settings.isEnabled {
            LTCStrip(
                item: activeItem,
                framerate: document.model.timecodeSettings.framerate,
                duration: activeItem.media.duration,
                engine: engine,
                zoom: waveformZoom
            )
            // Match the waveform's *total* playhead-track inset (outer gutter +
            // inner content inset) so the LTC playhead is collinear with the
            // waveform playhead (#663). The transport bar below stays full-bleed.
            .padding(.horizontal, PreviewLayout.playheadTrackInset)
        }
    }
}
