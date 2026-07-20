import XCTest
@testable import OnlyCue

/// #690 — the grandMA2 connection preferences. Only host + port are user-editable;
/// the console credentials are grandMA2's fixed defaults, so there is no
/// user-entered secret and no Keychain.
final class MA2ConnectionSettingsTests: XCTestCase {

    func test_appStorageKeys_andDefaults() {
        XCTAssertEqual(MA2ConnectionSettings.hostKey, "ma2Host")
        XCTAssertEqual(MA2ConnectionSettings.portKey, "ma2Port")
        // 30000 is the MA telnet remote port, not classic telnet 23.
        XCTAssertEqual(MA2ConnectionSettings.defaultPort, 30000)
    }

    func test_credentials_areTheGrandMA2Defaults() {
        // grandMA2 always ships the `administrator` account (it cannot be
        // deleted) and `admin` is its factory password — hardcoded so the user
        // never has to type or store console credentials.
        XCTAssertEqual(MA2ConnectionSettings.username, "administrator")
        XCTAssertEqual(MA2ConnectionSettings.password, "admin")
    }
}
