import SwiftUI

/// Small "MTC" pill beside the playhead clock, showing at a glance whether MIDI
/// Timecode is going out (epic #794).
///
/// Exists because the failure that matters — the destination vanishing — is
/// invisible otherwise: `MTCOutput` records it, but a Settings pane nobody has
/// open during a show cannot report it. (The LTC path has the same gap today,
/// with `LTCAudioOutput.lastError` published and unread; fixing that is filed
/// separately so this epic does not perturb the LTC path.)
///
/// Visibility follows the user's enable switch rather than whether output is
/// running, so an armed-but-idle rig is still visible and an unconfigured
/// install carries no dead chrome.
struct MTCStatusPill: View {

    @Environment(\.mtcOutput) private var output
    @ObservedObject private var store = MTCOutputStore.shared

    var body: some View {
        if MTCStatusLabel.isPillVisible(isEnabled: store.settings.isEnabled), let output {
            MTCStatusPillBody(output: output, isComplete: store.settings.isComplete)
        }
    }
}

/// The observing half. Split out so the pill can read an *optional* generator
/// from the environment while still tracking it as an `@ObservedObject` — a
/// property wrapper cannot be applied to an environment-read optional.
private struct MTCStatusPillBody: View {

    @ObservedObject var output: MTCOutput
    let isComplete: Bool

    private var state: MTCStatusLabel.State {
        MTCStatusLabel.state(isComplete: isComplete, isRunning: output.isRunning, lastError: output.lastError)
    }

    var body: some View {
        Text(MTCStatusLabel.pillText)
            .font(DS.Text.label)
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 1)   // off-grid: a pill hugging a caption-sized label; DS.Space.xs would double its height
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(background)
            )
            .accessibilityIdentifier("mtcPill")
            .accessibilityLabel(MTCStatusLabel.statusText(
                state: state,
                timecode: output.currentTimecode?.displayString,
                lastError: output.lastError
            ))
            .help(MTCStatusLabel.statusText(
                state: state,
                timecode: output.currentTimecode?.displayString,
                lastError: output.lastError
            ))
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
