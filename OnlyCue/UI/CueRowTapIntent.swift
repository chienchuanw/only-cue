import Foundation

/// What a single click on part of a cue row should do (#786).
///
/// A cue row is exactly three columns wide (`#`, `Name`, `Info`, the latter at
/// `maxWidth: .infinity`), so the columns cover the row end to end. Once a
/// plain click inside a column means "start typing here", the row has no mouse
/// path left to selection or to the playhead — so the leading cue-type colour
/// stripe takes that job and becomes the row's handle.
///
/// Kept free of SwiftUI so it can be unit-tested directly, the same split
/// `InlineEditGate` uses for the arrow-key shortcuts (#573).
enum CueRowTapTarget {
    /// One of the three text columns.
    case field
    /// The leading cue-type colour stripe.
    case stripe
}

enum CueRowTapIntent: Equatable {
    /// Select this row and put the caret in the tapped field. Never seeks.
    case beginEdit
    /// Toggle this row's membership of the selection. Never edits, never seeks.
    case extendSelection
    /// Select this row and move the playhead to its time.
    case selectAndSeek
    case ignored
}

enum CueRowTap {

    /// - Parameters:
    ///   - isExtending: whether ⌘ or ⇧ was held. Holding a modifier means
    ///     "I am selecting, not typing", the same reading
    ///     `CueMarkersOverlay.handleTap` already applies on the timeline.
    ///   - isReadOnly: Show mode. The columns are `.disabled` there, so they
    ///     receive no taps at all; the stripe stays live because it is the
    ///     only remaining way to jump the playhead from the cue list.
    static func intent(target: CueRowTapTarget,
                       isExtending: Bool,
                       isReadOnly: Bool) -> CueRowTapIntent {
        switch target {
        case .field:
            if isReadOnly { return .ignored }
            return isExtending ? .extendSelection : .beginEdit
        case .stripe:
            return isExtending ? .extendSelection : .selectAndSeek
        }
    }
}

/// Whether an inline name edit should be written, and as what (#786).
enum CueRowNameCommit {

    /// The value to write, or `nil` when nothing changed.
    ///
    /// Whitespace is trimmed, and an empty result is a legal name: #661 made an
    /// empty cue name render blank rather than "Untitled", so clearing the
    /// field is an edit the user meant.
    static func value(draft: String, current: String) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == current ? nil : trimmed
    }
}
