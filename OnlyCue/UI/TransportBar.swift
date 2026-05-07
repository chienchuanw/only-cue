import SwiftUI

struct TransportBar: View {

    let engine: PlayerEngine

    var body: some View {
        HStack(spacing: 12) {
            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.rate > 0 ? "pause.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
            .accessibilityIdentifier("playPauseButton")
            .accessibilityLabel(engine.rate > 0 ? "Pause" : "Play")

            Text(TimeFormat.hms(engine.currentTime))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("currentTimeReadout")
        }
    }
}
