import SwiftUI

/// The cue-list pane's footer while the document is in Show mode — a bottom-
/// pinned read-only indicator (Figma `318:1608`): a lock glyph + "Read-only —
/// Show Mode". Replaces the editable-mode `CueListFooter` (Manage Types…) when
/// the list is read-only. Its own file so `CueListPane` stays within the
/// SwiftLint `type_body_length` cap.
struct ShowModeFooter: View {

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "lock.fill")
            Text("Read-only — Show Mode")
        }
        .font(DS.Text.label)
        .foregroundStyle(DS.Color.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CueListLayout.rowHorizontalPadding)
        .padding(.vertical, DS.Space.sm)
        .accessibilityIdentifier("showModeReadOnlyFooter")
    }
}
