import SwiftUI

/// Trailing footer affordance for the cue list pane — currently just the
/// inline `Manage Types…` entry (audit §7.12 / #411). Lives in its own file
/// so `CueListPane` stays under SwiftLint's `type_body_length` cap.
struct CueListFooter: View {

    var body: some View {
        HStack {
            Spacer()
            Button("Manage Types…") {
                NotificationCenter.default.post(
                    name: .manageTypesRequested,
                    object: nil
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("cueListManageTypesInline")
        }
        .padding(.horizontal, CueListLayout.rowHorizontalPadding)
        .padding(.vertical, DS.Space.xs)
    }
}
