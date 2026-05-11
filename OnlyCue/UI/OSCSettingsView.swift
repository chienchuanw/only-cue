import AppKit
import SwiftUI

/// Settings → OSC pane: enable toggle, listen port, and a copyable list of the
/// supported address patterns. The toggle and port write to `@AppStorage`;
/// `OSCServerHost` (attached to each document window) observes the same keys
/// and starts/stops its `OSCServer` accordingly.
struct OSCSettingsView: View {

    @AppStorage(OSCServerSettings.enabledKey) private var enabled = false
    @AppStorage(OSCServerSettings.portKey) private var port = OSCServerSettings.defaultPort

    var body: some View {
        Form {
            Section {
                Toggle("Enable OSC server", isOn: $enabled)
                    .accessibilityIdentifier("oscEnableToggle")
                TextField("Listen port", value: $port, format: .number.grouping(.never))
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("oscPortField")
            } footer: {
                Text(
                    "Receive-only. Point Bitfocus Companion, a StreamDeck, or grandMA3 macros "
                    + "at this Mac's IP and port. macOS will ask to allow incoming connections "
                    + "the first time the server binds."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Supported address patterns") {
                ForEach(OSCCommand.supportedAddresses) { entry in
                    HStack {
                        Text(entry.displayPattern)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Copy") { copy(entry.address) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 360)
        .accessibilityIdentifier("oscSettings")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
