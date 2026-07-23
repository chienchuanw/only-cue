import XCTest
@testable import OnlyCue

/// `LTCRoutingStore` persists routing through `UserDefaults`. Runs against a
/// throwaway suite so the app's real `ltcRouting.v1` key is never touched.
@MainActor
final class LTCRoutingStoreTests: XCTestCase {

    private let suiteName = "com.chienchuanw.OnlyCue.LTCRoutingStoreTests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func test_freshStore_withNoStoredData_isDefault() {
        XCTAssertEqual(LTCRoutingStore(defaults: defaults).settings, .default)
    }

    func test_update_persistsAndSurvivesReload() {
        let store = LTCRoutingStore(defaults: defaults)
        let updated = LTCRoutingSettings(deviceUID: "uid-1", channelRoles: [.ltc, .trackLeft, .trackRight, .silent])
        store.update(updated)

        XCTAssertEqual(LTCRoutingStore(defaults: defaults).settings, updated)
        store.reload()
        XCTAssertEqual(store.settings, updated)
    }

    func test_update_toEqualValue_isNoOp() {
        let store = LTCRoutingStore(defaults: defaults)
        store.update(.default)
        XCTAssertNil(defaults.data(forKey: LTCRoutingStore.storageKey))
    }

    func test_resetToDefault_persists() {
        let store = LTCRoutingStore(defaults: defaults)
        store.update(LTCRoutingSettings(deviceUID: "uid", channelRoles: [.ltc]))
        store.resetToDefault()
        XCTAssertEqual(LTCRoutingStore(defaults: defaults).settings, .default)
    }

    func test_corruptStoredData_isReadAsDefault() {
        defaults.set(Data("garbage".utf8), forKey: LTCRoutingStore.storageKey)
        XCTAssertEqual(LTCRoutingStore(defaults: defaults).settings, .default)
    }

    /// UI-test persistence suppression must be scoped to the store the UI-test
    /// session configures — never process-global. Regression for #697: the
    /// suppression used to be a `static` flag that `UITestLTCHandler` flipped on
    /// whenever the CI marker `/tmp/.onlycue-ci-active` existed. A lingering
    /// marker (left by a hard-killed job) then no-op'd persistence for *every*
    /// store in the unit-test host, silently failing this suite.
    func test_uiTestSuppression_doesNotLeakToOtherStores() {
        // A store running hermetically for a UI-test session suppresses its own
        // persistence…
        let uiTestStore = LTCRoutingStore(defaults: defaults)
        uiTestStore.applyEphemeralForUITests(
            LTCRoutingSettings(deviceUID: "ephemeral", channelRoles: [.ltc]))

        // …but must NOT disable persistence for an independent store sharing the
        // same defaults. (Regression: suppression was once a process-global
        // static, so a lingering CI marker no-op'd persistence for every store.)
        let realStore = LTCRoutingStore(defaults: defaults)
        let updated = LTCRoutingSettings(deviceUID: "uid-1", channelRoles: [.ltc, .trackLeft])
        realStore.update(updated)

        XCTAssertEqual(LTCRoutingStore(defaults: defaults).settings, updated)
    }
}
