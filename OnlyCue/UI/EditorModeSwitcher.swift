import SwiftUI

/// The `Cue | Lyric | Show` segmented control shown at the top of the preview
/// pane. Always visible — the mode changes what waveform clicks do, so the user
/// must be able to read it at a glance. Built as an `HStack` of plain buttons
/// (rather than a segmented `Picker`) so each segment carries a stable
/// accessibility identifier and is reliably queryable in UI tests.
struct EditorModeSwitcher: View {

    let mode: EditorMode
    let setMode: (EditorMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EditorMode.allCases, id: \.self) { candidate in
                segment(candidate)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary))
        .fixedSize()
        // `.contain` keeps the switcher itself queryable AND lets XCUITest walk
        // to the individual segment buttons (same pattern as CueMarkersOverlay).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorModeSwitcher")
    }

    private func segment(_ candidate: EditorMode) -> some View {
        let isActive = candidate == mode
        return Button {
            setMode(candidate)
        } label: {
            Text(candidate.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? tint(candidate).opacity(0.9) : Color.clear)
                )
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editorModeSegment-\(candidate.rawValue)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// The per-mode tint that reinforces the active mode at a glance.
    private func tint(_ candidate: EditorMode) -> Color {
        switch candidate {
        case .cue: return .blue
        case .lyric: return .purple
        case .show: return .gray
        }
    }
}
