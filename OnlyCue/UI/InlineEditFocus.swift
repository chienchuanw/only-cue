import SwiftUI

/// Tracks whether an inline cue field (name / number / fade) in the cue list
/// is currently being edited, so the window-level bare arrow-key shortcuts can
/// step aside and let the text field's field editor move the caret (#573).
///
/// The signal travels via SwiftUI's focus chain: `CueRowView`'s editing
/// `TextField`s publish `editingCueField = true` through `.focusedValue`, and
/// `DocumentView` reads it with `@FocusedValue` to gate its hidden
/// shortcut-host buttons. A `FocusedValue` is the right tool here because it
/// reflects the key window's focused view regardless of where the shortcut
/// hosts sit in the view tree.
struct EditingCueFieldKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var editingCueField: Bool? {
        get { self[EditingCueFieldKey.self] }
        set { self[EditingCueFieldKey.self] = newValue }
    }
}

/// Pure gating logic for the bare arrow-key transport/step shortcuts. Kept
/// free of SwiftUI state so it can be unit-tested directly (#573).
enum InlineEditGate {

    /// Reduce the optional `@FocusedValue` to a definite "is a cue field being
    /// edited" boolean. Absent (`nil`) or `false` both mean "not editing".
    static func isEditing(_ focusedValue: Bool?) -> Bool {
        focusedValue == true
    }

    /// Whether the up/down step-cue shortcuts should be active: only when a
    /// media item is loaded and no inline cue field is being edited.
    static func stepShortcutsEnabled(hasActiveItem: Bool, isEditingCueField: Bool) -> Bool {
        hasActiveItem && !isEditingCueField
    }
}
