import SwiftUI

/// Transport-bar rate indicator + popover. Hidden when `rate == 1.0×` outside
/// the flash window. Flashes briefly on any rate change (including back to 1.0×)
/// and shows red interlock messages when LTC blocks/forces a rate reset.
struct PlaybackRateBadge: View {

    let engine: PlayerEngine

    @State private var flashUntil: Date = .distantPast
    @State private var interlockMessage: String?
    @State private var showPopover = false

    private static let flashDuration: TimeInterval = 1.2
    private static let interlockBlockedMessage = "Disable LTC to change playback rate."
    private static let interlockResetMessage = "Playback rate reset to 1.0× for LTC."

    private var rateText: String {
        String(format: "%.1f×", engine.playbackRate)
    }

    private var isFlashing: Bool { Date() < flashUntil }
    private var isAtNormalRate: Bool { abs(engine.playbackRate - 1.0) < 0.0001 }
    private var isVisible: Bool { !isAtNormalRate || isFlashing || interlockMessage != nil }

    var body: some View {
        Group {
            if isVisible {
                Button { showPopover.toggle() } label: {
                    Text(interlockMessage ?? rateText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(interlockMessage != nil ? Color.red : Color.secondary)
                        .accessibilityIdentifier("playbackRateBadge")
                }
                .buttonStyle(.plain)
                .help("Playback rate (click to adjust)")
                .popover(isPresented: $showPopover) {
                    PlaybackRatePopover(engine: engine)
                        .padding()
                }
            }
        }
        .onChange(of: engine.playbackRate) { _, _ in
            flashUntil = Date().addingTimeInterval(Self.flashDuration)
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackRateInterlockBlocked)) { _ in
            flashInterlock(Self.interlockBlockedMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackRateInterlockReset)) { _ in
            flashInterlock(Self.interlockResetMessage)
        }
    }

    private func flashInterlock(_ message: String) {
        interlockMessage = message
        let until = Date().addingTimeInterval(Self.flashDuration)
        flashUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) {
            if Date() >= until {
                interlockMessage = nil
            }
        }
    }
}

private struct PlaybackRatePopover: View {

    @Bindable var engine: PlayerEngine

    private var rateBinding: Binding<Double> {
        Binding(
            get: { Double(engine.playbackRate) },
            set: { engine.setPlaybackRate(Float($0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: "Speed: %.1f×", engine.playbackRate))
                .font(.system(.body, design: .monospaced))
            Slider(
                value: rateBinding,
                in: Double(PlayerEngine.playbackRateRange.lowerBound)...Double(PlayerEngine.playbackRateRange.upperBound),
                step: Double(PlayerEngine.playbackRateStep)
            )
            .frame(width: 220)
            .accessibilityIdentifier("playbackRateSlider")
            Button("Reset to 1.0×") { engine.resetPlaybackRate() }
                .accessibilityIdentifier("playbackRateResetButton")
        }
    }
}
