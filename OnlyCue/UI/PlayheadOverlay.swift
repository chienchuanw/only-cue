import SwiftUI

struct PlayheadOverlay: View {

    let currentTime: TimeInterval
    let duration: TimeInterval

    @Environment(\.projectFramerate) private var framerate

    private static let lineWidth: CGFloat = 1
    private static let labelWidth: CGFloat = 96
    private static let labelHeight: CGFloat = 18
    /// Y inset from the top of the overlay where the time label is anchored.
    /// Must be non-negative so the label stays inside the parent ScrollView's
    /// clipped frame (regression: a previous negative offset clipped it away).
    static let labelTopInset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = CueMarkersGeometry.position(
                forTime: currentTime,
                width: width,
                duration: duration
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: Self.lineWidth)
                    .offset(x: x - Self.lineWidth / 2)
                    .opacity(0.85)

                Text(TimeFormat.smpte(currentTime, rate: framerate))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .frame(width: Self.labelWidth, height: Self.labelHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.regularMaterial)
                    )
                    .offset(
                        x: Self.labelX(playheadX: x, labelWidth: Self.labelWidth, width: width),
                        y: Self.labelTopInset
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("playheadOverlay")
    }

    static func labelX(playheadX: CGFloat, labelWidth: CGFloat, width: CGFloat) -> CGFloat {
        let maxX = max(width - labelWidth, 0)
        let centered = playheadX - labelWidth / 2
        return min(max(centered, 0), maxX)
    }
}
