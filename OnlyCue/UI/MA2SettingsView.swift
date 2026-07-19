import SwiftUI

/// Settings → grandMA2 pane (#683): host, telnet port, and login for the
/// console that `File → Send to grandMA2…` pushes to. Host / port / username
/// write to `@AppStorage`; the password goes to the macOS Keychain only
/// (`MA2Keychain`), never UserDefaults.
struct MA2SettingsView: View {

    @AppStorage(MA2ConnectionSettings.hostKey) private var host = ""
    @AppStorage(MA2ConnectionSettings.portKey) private var port = MA2ConnectionSettings.defaultPort
    @AppStorage(MA2ConnectionSettings.usernameKey) private var username = MA2ConnectionSettings.defaultUsername

    @State private var password = ""
    @State private var passwordStatus: String?
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
                        Picker("", selection: $host) {
                            ForEach(discovered) { console in Text(console.host).tag(console.host) }
                        }
                        .labelsHidden()
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
                TextField("Username", text: $username)
                    .accessibilityIdentifier("ma2UsernameField")
                SecureField("Password", text: $password)
                    .accessibilityIdentifier("ma2PasswordField")
                    .onSubmit(savePassword)
                HStack {
                    Button("Save Password", action: savePassword)
                        .accessibilityIdentifier("ma2SavePasswordButton")
                    if let passwordStatus {
                        Text(passwordStatus)
                            .font(.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            } footer: {
                Text(
                    "The console (or onPC) must have Telnet set to \"Login Enabled\" in "
                    + "Setup → Console → Global Settings. The password is stored in the "
                    + "macOS Keychain. Port 30000 is the MA telnet remote."
                )
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 360)
        .accessibilityIdentifier("ma2Settings")
        .onAppear(perform: loadPassword)
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

    private func loadPassword() {
        password = (try? MA2Keychain.password(account: MA2ConnectionSettings.passwordAccount)) ?? ""
    }

    private func savePassword() {
        do {
            if password.isEmpty {
                try MA2Keychain.deletePassword(account: MA2ConnectionSettings.passwordAccount)
                passwordStatus = "Password cleared."
            } else {
                try MA2Keychain.setPassword(password, account: MA2ConnectionSettings.passwordAccount)
                passwordStatus = "Saved to Keychain."
            }
        } catch {
            passwordStatus = "Keychain error: \(error)"
        }
    }
}
