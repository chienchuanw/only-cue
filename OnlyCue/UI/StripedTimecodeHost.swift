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
    @State private var track: StripedTimecodeTrack?

    func body(content: Content) -> some View {
        content
            .environment(\.stripedTimecode, track)
            .task(id: item?.id) {
                track = nil
                track = await MediaImporter.stripedTimecode(for: item)
            }
    }
}

extension View {
    func stripedTimecodeReader(item: MediaItem?) -> some View {
        modifier(StripedTimecodeHost(item: item))
    }
}
