import SwiftUI

/// Sheet showing what the per-document `MIDIInput` is receiving: which device
/// it's connected to, the last error if any, and a newest-first tail of parsed
/// messages — including ones bound to nothing, which is exactly what you need
/// when finding out what CC number a fader actually sends. Presented from
/// `MIDIInputHost` (which owns the input) via `Tools → MIDI Monitor…`.
///
/// A sheet rather than a window, for the same reason as `OSCMonitorView`: the
/// input is per-document, so a standalone window would have to pick a document
/// to mirror.
struct MIDIMonitorView: View {

    let input: MIDIInput

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            recentMessagesSection
            HStack {
                Text(Self.messageCountText(count: input.recentMessages.count))
                    .font(.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .accessibilityIdentifier("midiMonitorMessageCount")
                Spacer()
                Button("Clear") { input.clearRecentMessages() }
                    .buttonStyle(.bordered)
                    .disabled(input.recentMessages.isEmpty)
                    .accessibilityIdentifier("midiMonitorClear")
            }
        }
        .padding()
        .frame(width: 480, height: 360)
        .accessibilityIdentifier("midiMonitor")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(input.isConnected ? Color.green : Color.secondary)
                .frame(width: 10, height: 10)
            Text(Self.statusText(isConnected: input.isConnected, deviceName: input.connectedName))
                .font(.headline)
            Spacer()
            if let error = input.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("midiMonitorStatus")
    }

    private var recentMessagesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent messages")
                .font(.subheadline.weight(.semibold))
            if input.recentMessages.isEmpty {
                emptyMessagesPlaceholder
            } else {
                messageList
            }
        }
        .accessibilityIdentifier("midiMonitorMessages")
    }

    private var emptyMessagesPlaceholder: some View {
        Text(input.isConnected
             ? "No messages received yet — move a fader or press a button."
             : "No MIDI input connected — choose one in Settings → MIDI.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(input.recentMessages.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, 2)
                        .background(
                            index.isMultiple(of: 2)
                                ? Color.clear
                                : DS.Color.surfaceSunken
                        )
                }
            }
        }
        .frame(maxHeight: 160)
    }

    /// The headline line in the monitor — names the connected device, or says
    /// none is selected. Pure; pinned by `MIDIMonitorTests`.
    static func statusText(isConnected: Bool, deviceName: String?) -> String {
        guard isConnected, let deviceName else { return "No MIDI input selected" }
        return "Connected · \(deviceName)"
    }

    /// Row-count footer. Pluralised: 0 messages / 1 message / N messages.
    static func messageCountText(count: Int) -> String {
        count == 1 ? "1 message" : "\(count) messages"
    }
}
