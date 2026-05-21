import SwiftUI

/// The `Cue | Lyric | Show` segmented control shown at the top of the preview
/// pane. Always visible — the mode changes what waveform clicks do. Achromatic
/// under Quiet Pro (ADR-024): the active segment uses the `ink` treatment, and
/// a leading SF Symbol carries mode identity by shape, not hue (ADR-023 amended).
/// Built as an `HStack` of plain buttons (rather than a segmented `Picker`) so
/// each segment carries a stable accessibility identifier.
struct EditorModeSwitcher: View {

    let mode: EditorMode
    let setMode: (EditorMode) -> Void

    var body: some View {
        HStack(spacing: DS.Space.xs / 2) {
            ForEach(EditorMode.allCases, id: \.self) { candidate in
                segment(candidate)
            }
        }
        .padding(DS.Space.xs / 2)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm + 1).fill(DS.Color.surfaceSunken))
        .fixedSize()
        // `.contain` keeps the switcher itself queryable AND lets XCUITest walk
        // to the individual segment buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorModeSwitcher")
    }

    private func segment(_ candidate: EditorMode) -> some View {
        let isActive = candidate == mode
        return Button {
            setMode(candidate)
        } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: candidate.symbolName)
                    .font(.system(size: 10, weight: .medium)) // off-grid: SF Symbol glyph size
                Text(candidate.title)
                    .font(DS.Text.body)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm - 1)
                    .fill(isActive ? DS.Color.ink : Color.clear)
            )
            .foregroundStyle(isActive ? DS.Color.inkOn : DS.Color.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editorModeSegment-\(candidate.rawValue)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
