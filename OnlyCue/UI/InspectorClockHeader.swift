import SwiftUI

/// Large, always-visible playhead readout pinned at the top of the Cue
/// Inspector pane. Reads `PlayerEngine.currentTime` (Observation-tracked) so
/// it ticks in lock-step with the transport, and renders as SMPTE timecode
/// at the project's configured framerate.
struct InspectorClockHeader: View {

    let engine: PlayerEngine
    @Environment(\.projectFramerate) private var framerate

    var body: some View {
        VStack(spacing: 8) {
            Text(TimeFormat.smpte(engine.currentTime, rate: framerate))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .accessibilityIdentifier("inspectorClock")
                .frame(maxWidth: .infinity, alignment: .center)
            Divider()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}
