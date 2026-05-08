import SwiftUI

struct CueMarkersOverlay: View {

    let cues: [Cue]
    let duration: TimeInterval
    var resolveColorHex: (Cue) -> String? = { _ in nil }
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

    let cue: Cue
    var resolvedColorHex: String?
    let baseX: CGFloat
    var onSeek: () -> Void = {}
    var onRetimeBy: (CGFloat) -> Void = { _ in }

    @State private var dragOffset: CGFloat = 0

    private static let lineWidth: CGFloat = 2
    private static let capHeight: CGFloat = 8
    private static let capWidth: CGFloat = 10
    private static let hitWidth: CGFloat = 14
    private static let dragThreshold: CGFloat = 4

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.clear)
                .frame(width: Self.hitWidth)
            Rectangle()
                .fill(markerColor)
                .frame(width: Self.lineWidth)
                .opacity(0.85)
            Capsule()
                .fill(markerColor)
                .frame(width: Self.capWidth, height: Self.capHeight)
        }
        .offset(x: baseX + dragOffset - Self.hitWidth / 2)
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
                    onSeek()
                } else {
                    onRetimeBy(dx)
                }
                dragOffset = 0
            }
    }
}
