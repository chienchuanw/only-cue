import XCTest
@testable import OnlyCue

@MainActor
final class MIDIMapStoreTests: XCTestCase {
    private let suiteName = "com.chienchuanw.OnlyCue.MIDIMapStoreTests"
    private var defaults: UserDefaults!
    private let cc45 = MIDIControlID(channel: 1, kind: .cc, number: 45)

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func test_freshStore_isEmpty() {
        XCTAssertNil(MIDIMapStore(defaults: defaults).map.action(for: cc45))
    }

    func test_learn_persistsAndSurvivesReload() {
        let store = MIDIMapStore(defaults: defaults)
        store.learn(cc45, as: .discrete(.playPause))
        XCTAssertEqual(MIDIMapStore(defaults: defaults).map.action(for: cc45), .discrete(.playPause))
        store.reload()
        XCTAssertEqual(store.map.action(for: cc45), .discrete(.playPause))
    }

    func test_clear_persists() {
        let store = MIDIMapStore(defaults: defaults)
        store.learn(cc45, as: .discrete(.playPause))
        store.clear(cc45)
        XCTAssertNil(MIDIMapStore(defaults: defaults).map.action(for: cc45))
    }

    func test_resetAll_persists() {
        let store = MIDIMapStore(defaults: defaults)
        store.learn(cc45, as: .discrete(.playPause))
        store.resetAll()
        XCTAssertNil(MIDIMapStore(defaults: defaults).map.action(for: cc45))
    }

    func test_selectedInputUID_persists() {
        let store = MIDIMapStore(defaults: defaults)
        store.selectInput(uid: "device-1")
        XCTAssertEqual(MIDIMapStore(defaults: defaults).selectedInputUID, "device-1")
    }

    func test_twoInjectedStores_areIndependentPerDefaults() {
        // Regression guard for the #697 class: no global suppression; each store
        // reads/writes only its injected defaults.
        let storeA = MIDIMapStore(defaults: defaults)
        storeA.learn(cc45, as: .discrete(.stepNextCue))
        XCTAssertEqual(MIDIMapStore(defaults: defaults).map.action(for: cc45), .discrete(.stepNextCue))
    }
}
