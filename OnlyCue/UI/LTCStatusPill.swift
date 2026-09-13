import SwiftUI

/// Small "LTC" pill beside the playhead clock, showing at a glance whether Linear
/// Timecode is going out (#796). The LTC twin of `MTCStatusPill`.
///
/// Exists because the failure that matters — the routed interface vanishing —
/// is invisible otherwise: `LTCAudioOutput` records it in `lastError`, but a
/// settings pane nobody has open during a show cannot report it.
///
/// Visibility follows the user's master enable switch rather than whether output
/// is running, so an armed-but-idle rig is still visible and an unconfigured
/// install carries no dead chrome.
struct LTCStatusPill: View {

    @Environment(\.ltcOutput) private var output
    @ObservedObject private var store = LTCRoutingStore.shared

    var body: some View {
        if LTCStatusLabel.isPillVisible(isEnabled: store.settings.isEnabled), let output {
            LTCStatusPillBody(output: output, isComplete: store.settings.isComplete)
        }
    }
}

/// The observing half. Split out so the pill can read an *optional* engine from
/// the environment while still tracking it as an `@ObservedObject` — a property
/// wrapper cannot be applied to an environment-read optional.
private struct LTCStatusPillBody: View {

    @ObservedObject var output: LTCAudioOutput
    let isComplete: Bool

    private var state: LTCStatusLabel.State {
        LTCStatusLabel.state(isComplete: isComplete, isRunning: output.isRunning, lastError: output.lastError)
    }

    var body: some View {
        Text(LTCStatusLabel.pillText)
            .font(DS.Text.label)
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 1)   // off-grid: a pill hugging a caption-sized label; DS.Space.xs would double its height
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(background)
            )
            .accessibilityIdentifier("ltcPill")
            .accessibilityLabel(statusText)
            .help(statusText)
    }

    private var statusText: String {
        // LTC publishes no live timecode; the label prints "Sending" without a
        // dash tail, and the adjacent playhead clock carries the readout.
        LTCStatusLabel.statusText(state: state, timecode: nil, lastError: output.lastError)
    }

    private var foreground: Color {
        switch state {
        case .failed:  return Color.white   // semantic: text on the failure fill — see `background`
        case .sending: return DS.Color.onCueIndigo
        case .ready, .off: return DS.Color.textTertiary
        }
    }

    private var background: Color {
        switch state {
        // The palette is deliberately achromatic (ADR-029) with cue-type colour as
        // its only chroma, so adding a `danger` token would widen the design system
        // for a single pill; the system red carries the convention instead.
        case .failed:  return Color.red   // semantic: failure is signalled by meaning, not by style
        case .sending: return DS.Color.cueIndigo
        case .ready, .off: return Color.clear
        }
    }
}
