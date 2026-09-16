import AppKit

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

/// Which selection gesture the held modifiers name (#790).
///
/// #786 read ⌘ and ⇧ as one `isExtending` flag, which made ⇧-click a toggle
/// and left the list with no contiguous range selection at all. They are two
/// gestures, so they are two cases.
enum CueRowTapModifier: CaseIterable {
    /// No selection modifier held.
    case plain
    /// ⌘ — add or remove this one row.
    case toggle
    /// ⇧ — select from the anchor to this row.
    case range
}

extension CueRowTapModifier {

    /// ⇧ is checked first: ⌘⇧ means "add the range to the selection" in Finder,
    /// which #790 does not ask for, so the range simply wins.
    init(flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift) {
            self = .range
        } else if flags.contains(.command) {
            self = .toggle
        } else {
            self = .plain
        }
    }
}

enum CueRowTapIntent: Equatable {
    /// Select this row and put the caret in the tapped field. Never seeks.
    case beginEdit
    /// Toggle this row's membership of the selection. Never edits, never seeks.
    case toggleSelection
    /// Select the rows between the anchor and this one, replacing the
    /// selection. Never edits, never seeks.
    case extendRange
    /// Select this row and move the playhead to its time.
    case selectAndSeek
    case ignored
}

enum CueRowTap {

    /// - Parameters:
    ///   - modifier: which selection gesture the click carries. Holding either
    ///     selection modifier means "I am selecting, not typing", the same
    ///     reading `CueMarkersOverlay.handleTap` already applies on the
    ///     timeline.
    ///   - isReadOnly: Show mode. The columns are `.disabled` there, so they
    ///     receive no taps at all; the stripe stays live because it is the
    ///     only remaining way to jump the playhead from the cue list.
    static func intent(target: CueRowTapTarget,
                       modifier: CueRowTapModifier,
                       isReadOnly: Bool) -> CueRowTapIntent {
        switch target {
        case .field:
            if isReadOnly { return .ignored }
            switch modifier {
            case .plain: return .beginEdit
            case .toggle: return .toggleSelection
            case .range: return .extendRange
            }
        case .stripe:
            switch modifier {
            case .plain: return .selectAndSeek
            case .toggle: return .toggleSelection
            case .range: return .extendRange
            }
        }
    }
}
