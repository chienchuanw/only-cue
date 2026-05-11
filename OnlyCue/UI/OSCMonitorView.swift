import SwiftUI

/// Sheet showing what the per-document `OSCServer` is doing: whether it's
/// bound and on which port, the last error if any, a newest-first tail of the
/// messages it has received (including ones that mapped to no command), and a
/// copyable list of the addresses OnlyCue understands. Presented from
/// `OSCServerHost` (which owns the server) via `Tools → OSC Monitor…`.
///
/// It's a sheet, not a free-floating window: the server is per-document
/// (ADR-016), so a standalone window would have to pick a document to mirror —
/// the sheet just mirrors the one it's attached to.
struct OSCMonitorView: View {

    let server: OSCServer

    @AppStorage(OSCServerSettings.portKey) private var port = OSCServerSettings.defaultPort
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            recentMessagesSection
            Divider()
            supportedAddressesSection
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480, height: 460)
        .accessibilityIdentifier("oscMonitor")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.isListening ? Color.green : Color.secondary)
                .frame(width: 10, height: 10)
            Text(Self.statusText(isListening: server.isListening, port: port))
                .font(.headline)
            Spacer()
            if let error = server.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("oscMonitorStatus")
    }

    private var recentMessagesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent messages")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Clear") { server.clearRecentMessages() }
                    .controlSize(.small)
                    .disabled(server.recentMessages.isEmpty)
            }
            if server.recentMessages.isEmpty {
                emptyMessagesPlaceholder
            } else {
                messageList
            }
        }
        .accessibilityIdentifier("oscMonitorMessages")
    }

    private var emptyMessagesPlaceholder: some View {
        Text(server.isListening
             ? "No messages received yet."
             : "The OSC server is off — enable it in Settings → OSC.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(server.recentMessages.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: 160)
    }

    private var supportedAddressesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Supported addresses")
                .font(.subheadline.weight(.semibold))
            OSCSupportedAddressList()
        }
    }

    /// The headline line in the monitor — names the port when bound, plain
    /// "Not listening" otherwise. Pure; pinned by `OSCMonitorTests`.
    static func statusText(isListening: Bool, port: Int) -> String {
        isListening ? "Listening on UDP \(port)" : "Not listening"
    }
}
