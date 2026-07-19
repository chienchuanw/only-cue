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
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(bytes: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    static func setPassword(_ password: String, account: String) throws {
        let passwordData = Data(password.utf8)
        let query = baseQuery(account: account)

        let update = [kSecValueData as String: passwordData]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw Failure.unexpectedStatus(updateStatus)
        }

        var add = query
        add[kSecValueData as String] = passwordData
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Failure.unexpectedStatus(addStatus)
        }
    }

    static func deletePassword(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.unexpectedStatus(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
