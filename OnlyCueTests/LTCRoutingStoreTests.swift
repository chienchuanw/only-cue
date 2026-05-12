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
}
