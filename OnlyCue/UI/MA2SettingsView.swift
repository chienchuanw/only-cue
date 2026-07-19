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

    var body: some View {
        Form {
            Section {
                TextField("Console IP / hostname", text: $host)
                    .accessibilityIdentifier("ma2HostField")
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
