import AppKit
import SwiftUI

struct CueMarkersOverlay: View {

    let cues: [Cue]
    let duration: TimeInterval
    var resolveColorHex: (Cue) -> String? = { _ in nil }
    var selectedCueIDs: Set<Cue.ID> = []
    /// Plain marker click → replace the selection with this cue.
    var onSelectCue: (Cue.ID) -> Void = { _ in }
    /// ⌘- (or ⇧-) marker click → toggle this cue in/out of the selection.
    var onToggleCue: (Cue.ID) -> Void = { _ in }
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(cues) { cue in
                    CueMarkerView(
                        cue: cue,
                        resolvedColorHex: resolveColorHex(cue),
                        baseX: CueMarkersGeometry.position(
                            forTime: cue.time,
                            width: geometry.size.width,
                            duration: duration
                        ),
                        isSelected: selectedCueIDs.contains(cue.id),
                        onSelect: { extending in
                            if extending { onToggleCue(cue.id) } else { onSelectCue(cue.id) }
                        },
                        onSeek: { onSeek(cue.time) },
                        onRetimeBy: { dx in
                            let newTime = CueMarkersGeometry.time(
                                originalTime: cue.time,
                                dx: dx,
                                width: geometry.size.width,
                                duration: duration
                            )
                            onRetime(cue.id, newTime)
                        }
                    )
                }
            }
        }
        .accessibilityIdentifier("cueMarkersOverlay")
    }
}

struct CueMarkerView: View {

    /// Layout dimensions for the marker line + cap. Selected markers emphasize via
    /// thicker line and larger cap; the type color (`markerColor`) is unchanged so
    /// the cue's CuePointType identity is preserved on selection.
    struct MarkerStyle: Equatable {
        let lineWidth: CGFloat
        let capWidth: CGFloat
        let capHeight: CGFloat

        static let normal = Self(lineWidth: 2, capWidth: 10, capHeight: 8)
        static let selected = Self(lineWidth: 3, capWidth: 14, capHeight: 12)

        static func style(isSelected: Bool) -> Self {
            isSelected ? .selected : .normal
        }
    }

    let cue: Cue
    var resolvedColorHex: String?
    let baseX: CGFloat
    var isSelected: Bool = false
    /// `true` when ⌘ or ⇧ was held during the click (extend the selection vs. replace it).
    var onSelect: (_ extending: Bool) -> Void = { _ in }
    var onSeek: () -> Void = {}
    var onRetimeBy: (CGFloat) -> Void = { _ in }

    @State private var dragOffset: CGFloat = 0

    private static let hitWidth: CGFloat = 14
    private static let dragThreshold: CGFloat = 4
    private static let labelGap: CGFloat = 1

    private var style: MarkerStyle { MarkerStyle.style(isSelected: isSelected) }

    var body: some View {
        VStack(spacing: Self.labelGap) {
            Text(FadeTime.formatNumber(cue.cueNumber))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityIdentifier("cueMarkerLabel-\(cue.id.uuidString)")
            ZStack(alignment: .top) {
                Capsule()
                    .fill(.clear)
                    .frame(width: Self.hitWidth)
                Rectangle()
                    .fill(markerColor)
                    .frame(width: style.lineWidth)
                    .opacity(0.85)
                Capsule()
                    .fill(markerColor)
                    .frame(width: style.capWidth, height: style.capHeight)
            }
        }
        // Pin the layout column to hitWidth so wide cueNumber labels (e.g. "99.5",
        // "100") don't expand the VStack and pull the line off baseX. The label's
        // `.fixedSize()` lets it overflow visually around the column's center while
        // the line stays anchored at the cue's exact time.
        .frame(width: Self.hitWidth)
        .offset(x: baseX + dragOffset - Self.hitWidth / 2)
        // Gesture intentionally on the VStack (not the inner ZStack) so clicking
        // anywhere — line, cap, label, or hit-capsule — drags or seeks the marker.
        .gesture(dragOrTapGesture)
        .accessibilityIdentifier("cueMarker-\(cue.id.uuidString)")
    }

    private var markerColor: Color {
        guard let hex = resolvedColorHex else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }

    private var dragOrTapGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let dx = value.translation.width
                if abs(dx) < Self.dragThreshold {
                    // Select first so the cue list highlight + inspector update
                    // land before the seek; engine.seek is idempotent so the
                    // CueListPane.onChange(of: selection) seek that follows is
                    // a redundant no-op against the same target time. ⌘/⇧ extends
                    // the selection instead of replacing it (no seek then).
                    let modifiers = NSEvent.modifierFlags
                    let extending = modifiers.contains(.command) || modifiers.contains(.shift)
                    onSelect(extending)
                    if !extending { onSeek() }
                } else {
                    onRetimeBy(dx)
                }
                dragOffset = 0
            }
    }
}
