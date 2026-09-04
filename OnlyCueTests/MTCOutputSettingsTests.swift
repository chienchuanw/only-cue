import XCTest
@testable import OnlyCue

/// `MTCOutputSettings` is the machine-level MTC configuration (epic #794) —
/// a master switch and one CoreMIDI destination. Mirrors `LTCRoutingSettings`
/// in shape, minus the channel-role layer MTC has no use for.
final class MTCOutputSettingsTests: XCTestCase {

    // A fresh install must emit nothing until the user opts in, matching
    // `LTCRoutingSettings.default`.
    func test_default_isDisabledWithNoDestination() {
        XCTAssertFalse(MTCOutputSettings.default.isEnabled)
        XCTAssertNil(MTCOutputSettings.default.destinationUID)
        XCTAssertFalse(MTCOutputSettings.default.isComplete)
    }

    func test_isComplete_requiresBothEnabledAndADestination() {
        XCTAssertFalse(MTCOutputSettings(isEnabled: true, destinationUID: nil).isComplete)
        XCTAssertFalse(MTCOutputSettings(isEnabled: false, destinationUID: "uid-1").isComplete)
        XCTAssertTrue(MTCOutputSettings(isEnabled: true, destinationUID: "uid-1").isComplete)
    }

    // MARK: - Transforms (value-returning — callers persist the result)

    func test_settingEnabled_leavesTheDestinationUntouched() {
        let settings = MTCOutputSettings(isEnabled: false, destinationUID: "uid-1")
        XCTAssertEqual(settings.settingEnabled(true),
                       MTCOutputSettings(isEnabled: true, destinationUID: "uid-1"))
    }

    func test_selectingDestination_leavesTheSwitchUntouched() {
        let settings = MTCOutputSettings(isEnabled: true, destinationUID: nil)
        XCTAssertEqual(settings.selectingDestination(uid: "uid-2"),
                       MTCOutputSettings(isEnabled: true, destinationUID: "uid-2"))
        XCTAssertEqual(settings.selectingDestination(uid: nil).destinationUID, nil)
    }

    // MARK: - Codable

    func test_codable_roundTrips() throws {
        let settings = MTCOutputSettings(isEnabled: true, destinationUID: "uid-7")
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(MTCOutputSettings.self, from: data), settings)
    }

    // Tolerate payloads written before a key existed, the same way
    // `LTCRoutingSettings` does — a missing switch reads as off, not as a
    // decode failure that silently resets the destination too.
    func test_decode_toleratesMissingKeys() throws {
        let data = Data("{}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(MTCOutputSettings.self, from: data), .default)

        let partial = Data(#"{"destinationUID":"uid-9"}"#.utf8)
        let decoded = try JSONDecoder().decode(MTCOutputSettings.self, from: partial)
        XCTAssertFalse(decoded.isEnabled)
        XCTAssertEqual(decoded.destinationUID, "uid-9")
    }
}

/// `MTCOutputStore` persists `MTCOutputSettings` through `UserDefaults`. Runs
/// against a throwaway suite so the app's real `mtcOutput.v1` key is untouched.
@MainActor
final class MTCOutputStoreTests: XCTestCase {

    private let suiteName = "com.chienchuanw.OnlyCue.MTCOutputStoreTests"
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
        XCTAssertEqual(MTCOutputStore(defaults: defaults).settings, .default)
    }

    func test_update_persistsAndSurvivesReload() {
        let store = MTCOutputStore(defaults: defaults)
        let updated = MTCOutputSettings(isEnabled: true, destinationUID: "uid-1")
        store.update(updated)

        XCTAssertEqual(MTCOutputStore(defaults: defaults).settings, updated)
        store.reload()
        XCTAssertEqual(store.settings, updated)
    }

    func test_update_toEqualValue_isNoOp() {
        let store = MTCOutputStore(defaults: defaults)
        store.update(.default)
        XCTAssertNil(defaults.data(forKey: MTCOutputStore.storageKey))
    }

    func test_corruptStoredData_fallsBackToDefault() {
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: MTCOutputStore.storageKey)
        XCTAssertEqual(MTCOutputStore(defaults: defaults).settings, .default)
    }

    func test_resetToDefault_clearsConfiguredSettings() {
        let store = MTCOutputStore(defaults: defaults)
        store.update(MTCOutputSettings(isEnabled: true, destinationUID: "uid-1"))
        store.resetToDefault()
        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(MTCOutputStore(defaults: defaults).settings, .default)
    }
}
