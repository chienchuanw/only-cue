import SwiftUI

/// Large, always-visible playhead readout pinned at the top of the
/// `CueListPane`. Reads `PlayerEngine.currentTime` (Observation-tracked)
/// so it ticks in lock-step with the transport, and renders as SMPTE
/// timecode at the project's configured framerate.
///
/// Previously named `InspectorClockHeader` and lived inside
/// `CueInspectorView`; now sits above the cue list directly (issue #293).
struct PlayheadClockHeader: View {

    let engine: PlayerEngine
    @Environment(\.projectFramerate) private var framerate

    var body: some View {
        VStack(spacing: 8) {
            Text(TimeFormat.smpte(engine.currentTime, rate: framerate))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .accessibilityIdentifier("playheadClock")
                .frame(maxWidth: .infinity, alignment: .center)
            Divider()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}
