import Foundation
import Security

/// Named `@AppStorage` keys for the grandMA2 connection (#683), following the
/// `OSCServerSettings` convention. The password is deliberately absent here —
/// it lives in the Keychain via `MA2Keychain`, never in UserDefaults.
enum MA2ConnectionSettings {
    static let hostKey = "ma2Host"
    static let portKey = "ma2Port"
    static let usernameKey = "ma2Username"

    /// The MA telnet remote port (not classic telnet 23).
    static let defaultPort = 30000
    static let defaultUsername = "administrator"
}

/// Minimal Keychain wrapper for the grandMA2 password: one generic-password
/// item per account under service `OnlyCue-MA2`.
enum MA2Keychain {

    static let service = "OnlyCue-MA2"

    enum Failure: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    static func password(account: String) throws -> String? {
        fatalError("unimplemented")
    }

    static func setPassword(_ password: String, account: String) throws {
        fatalError("unimplemented")
    }

    static func deletePassword(account: String) throws {
        fatalError("unimplemented")
    }
}
