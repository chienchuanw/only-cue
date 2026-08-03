import XCTest
@testable import OnlyCue

final class WorkspaceLayoutTests: XCTestCase {

    func test_default_givesEveryModeTheDefaultPaneLayout() {
        let workspace = WorkspaceLayout.default
        XCTAssertEqual(workspace.name, WorkspaceLayout.defaultName)
        for mode in EditorMode.allCases {
            XCTAssertEqual(workspace[mode], .default, "mode \(mode.rawValue)")
        }
    }

    func test_subscript_storesPerMode() {
        var workspace = WorkspaceLayout.default
        var lyric = PaneLayout.default
        lyric.inspectorWidth = 400
        workspace[.lyric] = lyric

        XCTAssertEqual(workspace[.lyric].inspectorWidth, 400)
        XCTAssertEqual(workspace[.cue].inspectorWidth, CueListInspectorMetrics.idealWidth)
    }

    func test_subscript_unsetMode_fallsBackToTheDefaultPaneLayout() throws {
        // A preset persisted by an older build that only knew two modes must
        // not crash or return garbage for the third.
        let json = #"{"name":"Legacy","layoutsByMode":{}}"#
        let workspace = try JSONDecoder().decode(
            WorkspaceLayout.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        XCTAssertEqual(workspace[.show], .default)
    }

    func test_encodesLayoutsAsAJSONObject_notAnArray() throws {
        // `[EditorMode: PaneLayout]` would encode as a flat ARRAY, because the
        // key is neither String nor Int as far as JSONEncoder is concerned.
        // Keying by `EditorMode.rawValue` keeps the on-disk shape a readable
        // object — which matters because decision 4 keeps file export cheap
        // to add later.
        let data = try JSONEncoder().encode(WorkspaceLayout.default)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let byMode = try XCTUnwrap(object?["layoutsByMode"] as? [String: Any])
        XCTAssertEqual(Set(byMode.keys), Set(EditorMode.allCases.map(\.rawValue)))
    }

    func test_roundTrip() throws {
        var workspace = WorkspaceLayout.default
        workspace.name = "Focus"
        workspace[.show] = PaneLayout(
            sidebarWidth: 300,
            isSidebarCollapsed: true,
            inspectorWidth: 400,
            isInspectorCollapsed: false
        )
        let data = try JSONEncoder().encode(workspace)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceLayout.self, from: data), workspace)
    }
}
