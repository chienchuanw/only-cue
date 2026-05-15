import SwiftUI

/// Lane shown below the waveform when LTC routing is enabled. A fixed-width
/// header carries the mute toggle + active clip's file name; the trailing
/// ruler draws `LTCTickGenerator` ticks + labels across the lane's width.
/// Strip is non-interactive (no hit testing on the ruler so clicks pass
/// through to the click-to-seek surface above).
struct LTCStrip: View {

    let item: MediaItem
    let framerate: SMPTEFramerate
    let duration: TimeInterval
    let onToggleMute: () -> Void

    private static let laneHeaderWidth: CGFloat = 140
    private static let stripHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            header
            ruler
        }
        .frame(height: Self.stripHeight)
        .background(Color.secondary.opacity(0.08))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ltcStrip")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onToggleMute) {
                Image(systemName: item.ltcMuted ? "speaker.slash.fill" : "speaker.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(item.ltcMuted ? "Unmute LTC for this clip" : "Mute LTC for this clip")
            .accessibilityLabel(item.ltcMuted ? "LTC muted" : "LTC unmuted")
            .accessibilityIdentifier("ltcMuteToggle.\(item.id.uuidString)")
            Text(item.resolvedName)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.laneHeaderWidth, alignment: .leading)
    }

    private var ruler: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(into: context, size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func draw(into context: GraphicsContext, size: CGSize) {
        guard duration > 0, size.width > 0 else { return }
        let pxPerSecond = size.width / CGFloat(duration)
        let bucket = LTCTickInterval.pick(secondsVisible: duration, pxPerSecond: pxPerSecond)
        let ticks = LTCTickGenerator.ticks(
            duration: duration,
            framerate: framerate,
            startTimecodeFrames: item.startTimecodeFrames,
            bucketSeconds: bucket,
            contentWidth: size.width
        )
        let strokeColor = GraphicsContext.Shading.color(.secondary)
        for tick in ticks {
            let tickHeight: CGFloat = tick.isMajor ? 10 : 6
            var path = Path()
            path.move(to: CGPoint(x: tick.xPosition, y: size.height))
            path.addLine(to: CGPoint(x: tick.xPosition, y: size.height - tickHeight))
            context.stroke(path, with: strokeColor, lineWidth: 1)
            let text = Text(tick.label)
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            context.draw(
                text,
                at: CGPoint(x: tick.xPosition + 2, y: size.height - tickHeight - 8),
                anchor: .topLeading
            )
        }
    }
}
