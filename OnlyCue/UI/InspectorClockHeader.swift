import SwiftUI

/// Large, always-visible playhead readout pinned at the top of the Cue
/// Inspector pane. Reads `PlayerEngine.currentTime` (Observation-tracked) so
/// it ticks in lock-step with the transport without a private timer.
struct InspectorClockHeader: View {

    let engine: PlayerEngine

    var body: some View {
        VStack(spacing: 8) {
            Text(Self.formatted(engine))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("inspectorClock")
            Divider()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    static func formatted(_ engine: PlayerEngine) -> String {
        TimeFormat.hms(engine.currentTime)
    }
}
