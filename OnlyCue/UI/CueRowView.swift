import SwiftUI

struct CueRowView: View {

    let index: Int
    let cue: Cue

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Circle()
                .fill(swatchColor)
                .frame(width: 12, height: 12)

            Text(cue.name.isEmpty ? "Untitled" : cue.name)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(TimeFormat.hms(cue.time))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("cueRow-\(index)")
    }

    private var swatchColor: Color {
        Color(hex: cue.colorHex) ?? .accentColor
    }
}
