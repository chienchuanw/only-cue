import SwiftUI

/// Section-header row above the cue list's column-header row. Renders the
/// uppercase `CUES` caption + a pluralised count pill, matching the Figma
/// reference and closing audit delta §7.6. Lives in its own file so
/// `CueListPane` stays under SwiftLint's `type_body_length` cap.
struct CueListSectionHeader: View {

    let count: Int

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text("Cues")
                .dsSectionHeader()
                .accessibilityIdentifier("cueListSectionCaption")
            Spacer(minLength: DS.Space.xs)
            Text(Self.countText(for: count))
                .font(DS.Text.label)
                .foregroundStyle(DS.Color.textSecondary)
                .monospacedDigit()
                .accessibilityIdentifier("cueListSectionCount")
        }
        .padding(.horizontal, CueListLayout.rowHorizontalPadding)
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("cueListSectionHeader")
    }

    /// Pure pluralisation helper — extracted so the contract is unit-testable
    /// without standing up a SwiftUI hosting view.
    static func countText(for count: Int) -> String {
        count == 1 ? "1 cue" : "\(count) cues"
    }
}
