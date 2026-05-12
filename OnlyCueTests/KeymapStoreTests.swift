import XCTest
@testable import OnlyCue

/// `KeymapStore` persists the keymap through `UserDefaults`. These run against a
/// throwaway suite so the app's real `keymap.v1` key is never touched.
@MainActor
final class KeymapStoreTests: XCTestCase {

    private let suiteName = "com.chienchuanw.OnlyCue.KeymapStoreTests"
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
        XCTAssertEqual(KeymapStore(defaults: defaults).keymap, .default)
    }

    func test_rebind_persistsAndSurvivesReload() throws {
        let store = KeymapStore(defaults: defaults)
        let chord = KeyChord(key: "k", modifiers: [.command, .shift])
        store.rebind(.duplicateCueAtPlayhead, to: chord)

        // A brand-new store reading the same defaults sees the change.
        let reopened = KeymapStore(defaults: defaults)
        XCTAssertEqual(reopened.keymap.chord(for: .duplicateCueAtPlayhead), chord)

        store.reload()
        XCTAssertEqual(store.keymap.chord(for: .duplicateCueAtPlayhead), chord)
    }

    func test_resetAll_persists() {
        let store = KeymapStore(defaults: defaults)
        store.rebind(.exportCues, to: KeyChord(key: "q"))
        store.resetAll()
        XCTAssertEqual(KeymapStore(defaults: defaults).keymap, .default)
    }

    func test_corruptStoredData_isReadAsDefault() {
        defaults.set(Data("garbage".utf8), forKey: KeymapStore.storageKey)
        XCTAssertEqual(KeymapStore(defaults: defaults).keymap, .default)
    }
}
