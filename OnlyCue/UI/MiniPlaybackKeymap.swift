import Foundation

/// The playback/navigation commands the Mini Player accepts from the keyboard
/// (#743). A deliberate whitelist — editing actions (`addCue`, cue-type digits)
/// are never keyboard-driven from the Mini Player.
enum MiniPlaybackAction: Equatable {
    case playPause, jumpBack, jumpForward, stepPrevCue, stepNextCue, go, rateUp, rateDown, rateReset
}

/// Resolves a key chord to a Mini Player playback action, honoring the user's
/// live `KeymapStore` bindings. Pure — the `NSEvent` glue converts an event to a
/// `KeyChord` and calls this.
enum MiniPlaybackKeymap {

    /// The `KeymapAction`s the Mini Player honors, paired with the action they map to.
    private static let whitelist: [(KeymapAction, MiniPlaybackAction)] = [
        (.playPause, .playPause),
        (.jumpBack, .jumpBack),
        (.jumpForward, .jumpForward),
        (.stepPrevCue, .stepPrevCue),
        (.stepNextCue, .stepNextCue),
        (.go, .go),
        (.playbackRateUp, .rateUp),
        (.playbackRateDown, .rateDown),
        (.playbackRateReset, .rateReset)
    ]

    static func action(for chord: KeyChord, keymap: Keymap) -> MiniPlaybackAction? {
        whitelist.first { keymap.chord(for: $0.0) == chord }?.1
    }
}
