import Foundation

/// Every user-rebindable command in OnlyCue.
///
/// The `rawValue` is the **stable JSON key** in the persisted keymap — never
/// rename a case without a migration, or older keymap files lose that binding
/// (they fall back to the default for the renamed action, see `Keymap`).
enum KeymapAction: String, CaseIterable, Codable, Identifiable, Sendable {
    // File menu
    case importMedia
    case exportCues
    // View menu — waveform zoom (horizontal)
    case waveformZoomIn
    case waveformZoomOut
    case waveformZoomReset
    // View menu — waveform zoom (vertical)
    case waveformVerticalZoomIn
    case waveformVerticalZoomOut
    case waveformVerticalZoomReset
    // View menu — toggles
    case toggleNotesOverlay
    case toggleTimelineBreakdown
    case toggleTempoGrid
    case togglePauseAtEachCue
    // View menu — selected-cue editing
    case snapSelectedCueToPlayhead
    case snapSelectedCuesToBeat
    case snapSelectedCuesToBar
    case duplicateCueAtPlayhead
    case nudgeSelectedCueBack
    case nudgeSelectedCueForward
    // Document window — playback & cue navigation
    case playPause
    case jumpBack
    case jumpForward
    case stepPrevCue
    case stepNextCue
    case addCue
    // Document window — create a cue of the Nth CuePointType (epic #32 cue model rework)
    case addCueOfType0
    case addCueOfType1
    case addCueOfType2
    case addCueOfType3
    case addCueOfType4
    case addCueOfType5
    case addCueOfType6
    case addCueOfType7
    case addCueOfType8
    case addCueOfType9

    var id: String { rawValue }

    /// Human-readable label for the Settings → Keyboard table. Data-driven (a
    /// `switch` over every case would blow the `cyclomatic_complexity` cap).
    var displayName: String { Self.displayNames[self] ?? rawValue }

    /// The `addCueOfTypeN` action for digit `0`…`9` (the document window's
    /// number-key cue-creation hotkeys), or `nil` if `digit` is out of range.
    static func addCueOfType(_ digit: Int) -> Self? {
        cueTypeSlots.indices.contains(digit) ? cueTypeSlots[digit] : nil
    }

    private static let cueTypeSlots: [Self] = [
        .addCueOfType0, .addCueOfType1, .addCueOfType2, .addCueOfType3, .addCueOfType4,
        .addCueOfType5, .addCueOfType6, .addCueOfType7, .addCueOfType8, .addCueOfType9
    ]

    private static let displayNames: [Self: String] = [
        .importMedia: "Import Media…",
        .exportCues: "Export Cues…",
        .waveformZoomIn: "Zoom In",
        .waveformZoomOut: "Zoom Out",
        .waveformZoomReset: "Actual Size",
        .waveformVerticalZoomIn: "Zoom In Vertically",
        .waveformVerticalZoomOut: "Zoom Out Vertically",
        .waveformVerticalZoomReset: "Actual Vertical Size",
        .toggleNotesOverlay: "Show Notes Overlay",
        .toggleTimelineBreakdown: "Show Timeline Breakdown",
        .toggleTempoGrid: "Show Tempo Grid",
        .togglePauseAtEachCue: "Pause at Each Cue",
        .snapSelectedCueToPlayhead: "Snap Selected Cue to Playhead",
        .snapSelectedCuesToBeat: "Snap Selected Cues to Nearest Beat",
        .snapSelectedCuesToBar: "Snap Selected Cues to Nearest Bar",
        .duplicateCueAtPlayhead: "Duplicate Cue at Playhead",
        .nudgeSelectedCueBack: "Nudge Selected Cue Back",
        .nudgeSelectedCueForward: "Nudge Selected Cue Forward",
        .playPause: "Play / Pause",
        .jumpBack: "Jump Back 1 Second",
        .jumpForward: "Jump Forward 1 Second",
        .stepPrevCue: "Go to Previous Cue",
        .stepNextCue: "Go to Next Cue",
        .addCue: "Add Cue at Playhead",
        .addCueOfType0: "Add Cue of Type 0",
        .addCueOfType1: "Add Cue of Type 1",
        .addCueOfType2: "Add Cue of Type 2",
        .addCueOfType3: "Add Cue of Type 3",
        .addCueOfType4: "Add Cue of Type 4",
        .addCueOfType5: "Add Cue of Type 5",
        .addCueOfType6: "Add Cue of Type 6",
        .addCueOfType7: "Add Cue of Type 7",
        .addCueOfType8: "Add Cue of Type 8",
        .addCueOfType9: "Add Cue of Type 9"
    ]
}
