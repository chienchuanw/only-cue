import Foundation
import Security

/// grandMA2 connection settings (#683, simplified in #690). Only the host and
/// telnet port are user-editable (`@AppStorage`). The console credentials are
/// grandMA2's fixed defaults — the `administrator` account always exists and
/// cannot be deleted, and `admin` is its factory password — so the user never
/// types or stores credentials and there is no secret to protect.
///
/// Trade-off: an operator *can* change the administrator password in the
/// console's user management; such a console fails login with `Login incorrect`
/// and has no in-app override. Accepted — our push targets run the default.
enum MA2ConnectionSettings {
    static let hostKey = "ma2Host"
    static let portKey = "ma2Port"

    /// The MA telnet remote port (not classic telnet 23).
    static let defaultPort = 30000

    /// Fixed grandMA2 console credentials.
    static let username = "administrator"
    static let password = "admin"

    // MARK: - Legacy cleanup

    /// Removes the console password older builds stored in the Keychain (#683's
    /// generic-password item). Credentials are hardcoded now, so a stored secret
    /// would just be abandoned there. No-op when nothing was saved; safe to call
    /// on every launch.
    static func removeLegacyKeychainPassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "OnlyCue-MA2",
            kSecAttrAccount as String: "grandMA2"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
