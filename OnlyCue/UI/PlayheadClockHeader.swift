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
                // Issue #297: a fixed 30pt monospaced timecode reports a
                // large intrinsic minimum width. Without bounding it, that
                // min can exceed the inspector column minimum and feed the
                // NSSplitView constraint loop during divider tracking.
                // lineLimit + minimumScaleFactor lets it shrink instead of
                // forcing the hosting view's min width up.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("playheadClock")
                .frame(maxWidth: .infinity, alignment: .center)
            Divider()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }
}
