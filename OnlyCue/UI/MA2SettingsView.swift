import SwiftUI

/// Settings → grandMA2 pane (#683, simplified in #690): the console host and
/// telnet port that `File → Send to grandMA2…` pushes to. Credentials are not
/// shown — OnlyCue signs in with grandMA2's fixed default `administrator`
/// account, so there is nothing for the user to type or store.
struct MA2SettingsView: View {

    @AppStorage(MA2ConnectionSettings.hostKey) private var host = ""
    @AppStorage(MA2ConnectionSettings.portKey) private var port = MA2ConnectionSettings.defaultPort

    @State private var discovered: [MA2Console] = []
    @State private var isScanning = false
    @State private var scanNote: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Console IP / hostname", text: $host)
                        .accessibilityIdentifier("ma2HostField")
                    if !discovered.isEmpty {
                        // A Menu of buttons (not a Picker bound to $host) so a
                        // manually-typed host that isn't in the discovered list
                        // doesn't trigger SwiftUI's "no matching tag" warning.
                        Menu("Discovered") {
                            ForEach(discovered) { console in
                                Button(console.host) { host = console.host }
                            }
                        }
                        .frame(width: 150)
                        .accessibilityIdentifier("ma2HostPicker")
                    }
                    Button(isScanning ? "Scanning…" : "Scan", action: scan)
                        .disabled(isScanning)
                        .accessibilityIdentifier("ma2ScanButton")
                }
                if let scanNote {
                    Text(scanNote)
                        .font(.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                TextField("Telnet port", value: $port, format: .number.grouping(.never))
                    .frame(maxWidth: 120)
                    .accessibilityIdentifier("ma2PortField")
            } footer: {
                Text(
                    "The console (or onPC) must have Telnet set to \"Login Enabled\" in "
                    + "Setup → Console → Global Settings. OnlyCue signs in with grandMA2's "
                    + "default \"administrator\" account. Port 30000 is the MA telnet remote."
                )
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 300)
        .accessibilityIdentifier("ma2Settings")
    }

    private func scan() {
        isScanning = true
        scanNote = nil
        Task {
            let found = await MA2ConsoleScanner.scan()
            await MainActor.run {
                discovered = found
                isScanning = false
                if found.isEmpty {
                    let subnets = MA2ConsoleScanner.localSubnets().map { "\($0).0/24" }.joined(separator: ", ")
                    scanNote = subnets.isEmpty
                        ? "No active network interfaces to scan."
                        : "No consoles found on \(subnets)."
                } else if host.isEmpty, let first = found.first {
                    host = first.host
                }
            }
        }
    }
}
