import SwiftUI

struct CueMarkersOverlay: View {

    let cues: [Cue]
    let duration: TimeInterval
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetime: (Cue.ID, TimeInterval) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(cues) { cue in
                    CueMarkerView(
                        cue: cue,
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
        .allowsHitTesting(true)
        .accessibilityIdentifier("cueMarkersOverlay")
    }
}

struct CueMarkerView: View {

    let cue: Cue
    let baseX: CGFloat
    var onSeek: () -> Void = {}
    var onRetimeBy: (CGFloat) -> Void = { _ in }

    @State private var dragOffset: CGFloat = 0

    private static let lineWidth: CGFloat = 2
    private static let capHeight: CGFloat = 8
    private static let capWidth: CGFloat = 10
    private static let hitWidth: CGFloat = 14

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.clear)
                .frame(width: Self.hitWidth)
                .contentShape(Rectangle())
            Rectangle()
                .fill(markerColor)
                .frame(width: Self.lineWidth)
                .opacity(0.85)
            Capsule()
                .fill(markerColor)
                .frame(width: Self.capWidth, height: Self.capHeight)
        }
        .offset(x: baseX + dragOffset - Self.hitWidth / 2)
        .gesture(dragGesture, including: .all)
        .onTapGesture { onSeek() }
        .accessibilityIdentifier("cueMarker-\(cue.id.uuidString)")
    }

    private var markerColor: Color {
        Color(hex: cue.colorHex) ?? .accentColor
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                onRetimeBy(value.translation.width)
                dragOffset = 0
            }
    }
}
