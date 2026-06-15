import SwiftUI

/// The `Cue | Lyric | Show` segmented control shown at the top of the preview
/// pane. Always visible — the mode changes what waveform clicks do. Achromatic
/// under Quiet Pro (ADR-024): the active segment uses the `ink` treatment, and
/// a leading SF Symbol carries mode identity by shape, not hue (ADR-023 amended).
/// Built as an `HStack` of plain buttons (rather than a segmented `Picker`) so
/// each segment carries a stable accessibility identifier.
struct EditorModeSwitcher: View {

    /// Switcher-bar spacing, pinned to Figma (#552, audit `## switcher-bar`).
    /// Off-grid (no DS token) — the design uses 3/5/11/5px values that don't sit
    /// on the 4px grid; `EditorModeSwitcherMetricsTests` guards them.
    enum Metrics {
        static let trackPadding: CGFloat = 3
        static let segmentGap: CGFloat = 5
        static let segmentHPadding: CGFloat = 11
        static let segmentVPadding: CGFloat = 5
        static let iconLabelGap: CGFloat = 5
        static let iconSize: CGFloat = 13
    }

    let mode: EditorMode
    let setMode: (EditorMode) -> Void

    var body: some View {
        HStack(spacing: Metrics.segmentGap) { // off-grid: Figma switcher gap-5
            ForEach(EditorMode.allCases, id: \.self) { candidate in
                segment(candidate)
            }
        }
        .padding(Metrics.trackPadding) // off-grid: Figma switcher padding 3
        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.surfaceSunken))
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
            HStack(spacing: Metrics.iconLabelGap) { // off-grid: Figma gap-5
                Image(systemName: candidate.symbolName)
                    .font(.system(size: Metrics.iconSize, weight: .medium)) // off-grid: Figma icon size-[13px]
                Text(candidate.title)
                    .font(DS.Text.body)
                    .fontWeight(.semibold) // Figma: semibold labels throughout
            }
            .padding(.horizontal, Metrics.segmentHPadding) // off-grid: Figma px-11
            .padding(.vertical, Metrics.segmentVPadding) // off-grid: Figma py-5
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
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
