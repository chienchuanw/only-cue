import XCTest
@testable import OnlyCue

@MainActor
final class WorkspaceLayoutStoreTests: XCTestCase {

    private let suiteName = "com.chienchuanw.OnlyCue.workspaceLayoutStoreTests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try super.tearDownWithError()
    }

    private func makeStore() -> WorkspaceLayoutStore {
        WorkspaceLayoutStore(defaults: defaults)
    }

    // MARK: - Fresh state

    func test_freshLaunch_holdsOnlyTheBuiltInDefault() {
        let store = makeStore()
        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
        XCTAssertEqual(store.state.mostRecentLayout, .default)
    }

    func test_corruptData_fallsBackToDefaultWithNoError() {
        defaults.set(Data("not json".utf8), forKey: WorkspaceLayoutStore.storageKey)
        let store = makeStore()
        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
    }

    // MARK: - Save / select

    func test_save_addsThePresetAndSelectsIt() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        focus[.lyric] = PaneLayout(
            sidebarWidth: 300,
            isSidebarCollapsed: false,
            inspectorWidth: 400,
            isInspectorCollapsed: false
        )
        store.save(focus)

        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Focus"])
        XCTAssertEqual(store.state.selectedName, "Focus")
    }

    func test_save_persistsAcrossStoreInstances() {
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        focus[.show] = PaneLayout(
            sidebarWidth: 320,
            isSidebarCollapsed: false,
            inspectorWidth: 340,
            isInspectorCollapsed: true
        )
        makeStore().save(focus)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.state.presets.count, 2)
        XCTAssertEqual(reloaded.state.presets[1][.show].inspectorWidth, 340)
        XCTAssertTrue(reloaded.state.presets[1][.show].isInspectorCollapsed)
        XCTAssertEqual(reloaded.state.selectedName, "Focus")
    }

    func test_save_withAnExistingName_replacesRatherThanDuplicates() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        focus[.cue].inspectorWidth = 400
        store.save(focus)

        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Focus"])
        XCTAssertEqual(store.state.presets[1][.cue].inspectorWidth, 400)
    }

    // MARK: - The built-in preset is protected

    func test_delete_refusesTheBuiltInDefault() {
        let store = makeStore()
        store.delete(WorkspaceLayout.defaultName)
        XCTAssertEqual(store.state.presets, [.default])
    }

    func test_overwrite_refusesTheBuiltInDefault() {
        let store = makeStore()
        var mutated = PaneLayout.default
        mutated.inspectorWidth = 400
        store.overwrite(name: WorkspaceLayout.defaultName,
                        with: .uniform(name: WorkspaceLayout.defaultName, layout: mutated))
        XCTAssertEqual(store.state.presets, [.default])
    }

    func test_rename_refusesTheBuiltInDefault() {
        let store = makeStore()
        store.rename(WorkspaceLayout.defaultName, to: "Mine")
        XCTAssertEqual(store.state.presets.map(\.name), ["Default"])
    }

    // MARK: - Rename / delete

    func test_rename_movesThePresetAndFollowsTheSelection() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        store.rename("Focus", to: "Tight")

        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Tight"])
        XCTAssertEqual(store.state.selectedName, "Tight")
    }

    func test_rename_toAnExistingName_isRefused() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        var wide = WorkspaceLayout.default
        wide.name = "Wide"
        store.save(wide)

        store.rename("Focus", to: "Wide")
        XCTAssertEqual(store.state.presets.map(\.name), ["Default", "Focus", "Wide"])
    }

    func test_delete_removesThePresetAndClearsTheSelection() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        store.delete("Focus")

        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
    }

    // MARK: - Live layout

    func test_recordLiveLayout_doesNotTouchTheSelectedPreset() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)

        var dragged = focus
        dragged[.cue].inspectorWidth = 400
        store.recordLiveLayout(dragged)

        XCTAssertEqual(store.state.mostRecentLayout[.cue].inspectorWidth, 400)
        XCTAssertEqual(store.state.presets[1][.cue].inspectorWidth,
                       CueListInspectorMetrics.idealWidth,
                       "a drag must never rewrite the selected preset (spec scenario: snapshot, not live binding)")
        XCTAssertEqual(store.state.selectedName, "Focus")
    }

    func test_recordLiveLayout_survivesRelaunchSoNewWindowsInheritIt() {
        var dragged = WorkspaceLayout.default
        dragged[.cue].isInspectorCollapsed = true
        makeStore().recordLiveLayout(dragged)

        XCTAssertTrue(makeStore().state.mostRecentLayout[.cue].isInspectorCollapsed)
    }

    func test_recordLiveLayout_withNoChange_doesNotRepersist() {
        let store = makeStore()
        store.recordLiveLayout(.default)
        let before = defaults.data(forKey: WorkspaceLayoutStore.storageKey)
        store.recordLiveLayout(.default)
        XCTAssertEqual(defaults.data(forKey: WorkspaceLayoutStore.storageKey), before)
    }

    // MARK: - Reset

    func test_resetToDefault_clearsPresetsAndSelection() {
        let store = makeStore()
        var focus = WorkspaceLayout.default
        focus.name = "Focus"
        store.save(focus)
        store.resetToDefault()

        XCTAssertEqual(store.state.presets, [.default])
        XCTAssertNil(store.state.selectedName)
        XCTAssertEqual(store.state.mostRecentLayout, .default)
    }
}
