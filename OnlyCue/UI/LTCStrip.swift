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

    private static let laneHeaderWidth: CGFloat = 150
    private static let stripHeight: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            header
            ruler
        }
        .frame(height: Self.stripHeight)
        .background(DS.Color.surfaceSunken)
        // Figma 318:1308 — the strip is bounded top and bottom by a hairline.
        .dsHairline(edge: .top)
        .dsHairline(edge: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ltcStrip")
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Button(action: onToggleMute) {
                Image(systemName: item.ltcMuted ? "speaker.slash.fill" : "speaker.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(item.ltcMuted ? "Unmute LTC for this clip" : "Mute LTC for this clip")
            .accessibilityLabel(item.ltcMuted ? "LTC muted" : "LTC unmuted")
            .accessibilityIdentifier("ltcMuteToggle.\(item.id.uuidString)")
            Text("LTC · \(item.resolvedName)")
                .font(DS.Text.monoSmall)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(width: Self.laneHeaderWidth, alignment: .leading)
        // The header block is panel-tinted; the ruler area keeps the sunken fill.
        .frame(maxHeight: .infinity)
        .background(DS.Color.panel)
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
        // Figma 318:1308: ticks are bottom-aligned in `border-strong` (major 9 /
        // minor 5) with a 2pt bottom inset; labels sit at the top in tertiary.
        let bottomInset: CGFloat = 2
        let strokeColor = GraphicsContext.Shading.color(DS.Color.borderStrong)
        for tick in ticks {
            let tickHeight: CGFloat = tick.isMajor ? 9 : 5
            let baseY = size.height - bottomInset
            var path = Path()
            path.move(to: CGPoint(x: tick.xPosition, y: baseY))
            path.addLine(to: CGPoint(x: tick.xPosition, y: baseY - tickHeight))
            context.stroke(path, with: strokeColor, lineWidth: 1)
            guard tick.isMajor else { continue }
            let text = Text(tick.label)
                .font(DS.Text.monoMicro)
                .foregroundColor(DS.Color.textTertiary)
            context.draw(
                text,
                at: CGPoint(x: tick.xPosition + 2, y: 3),
                anchor: .topLeading
            )
        }
    }
}
