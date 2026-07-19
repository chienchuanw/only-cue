import XCTest
@testable import OnlyCue

/// #683 — the grandMA2 connection preferences. Host / port / username live in
/// `@AppStorage`; the password lives in the macOS Keychain only (generic
/// password, service `OnlyCue-MA2`) — never in UserDefaults.
final class MA2ConnectionSettingsTests: XCTestCase {

    func test_appStorageKeys_andDefaults() {
        XCTAssertEqual(MA2ConnectionSettings.hostKey, "ma2Host")
        XCTAssertEqual(MA2ConnectionSettings.portKey, "ma2Port")
        XCTAssertEqual(MA2ConnectionSettings.usernameKey, "ma2Username")
        // 30000 is the MA telnet remote port, not classic telnet 23.
        XCTAssertEqual(MA2ConnectionSettings.defaultPort, 30000)
        XCTAssertEqual(MA2ConnectionSettings.defaultUsername, "administrator")
    }

    func test_keychain_roundTrip_update_delete() throws {
        // A test-only account name keeps this clear of any real saved password.
        let account = "test-\(UUID().uuidString)"
        defer { try? MA2Keychain.deletePassword(account: account) }

        XCTAssertNil(try MA2Keychain.password(account: account))

        try MA2Keychain.setPassword("first", account: account)
        XCTAssertEqual(try MA2Keychain.password(account: account), "first")

        // Saving again overwrites, not duplicates.
        try MA2Keychain.setPassword("second", account: account)
        XCTAssertEqual(try MA2Keychain.password(account: account), "second")

        try MA2Keychain.deletePassword(account: account)
        XCTAssertNil(try MA2Keychain.password(account: account))
    }

    func test_keychain_deleteMissing_isNoop() {
        XCTAssertNoThrow(try MA2Keychain.deletePassword(account: "test-never-saved-\(UUID().uuidString)"))
    }

    func test_passwordAccount_isFixed() {
        // One console password per Mac; a fixed account name keeps the lookup
        // independent of the (editable) username field.
        XCTAssertEqual(MA2ConnectionSettings.passwordAccount, "grandMA2")
    }

    func test_keychain_service_isOnlyCueMA2() {
        XCTAssertEqual(MA2Keychain.service, "OnlyCue-MA2")
    }
}
