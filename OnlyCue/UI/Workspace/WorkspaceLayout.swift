import SwiftUI

/// A named snapshot of the pane arrangement for every editor mode.
///
/// A preset is a snapshot, not a live binding (spec scope item 6): dragging a
/// divider after selecting "Focus" changes the window, never "Focus".
struct WorkspaceLayout: Codable, Equatable, Identifiable {

    var name: String

    /// Keyed by `EditorMode.rawValue`, not by `EditorMode`. `JSONEncoder`
    /// encodes a dictionary whose key is neither `String` nor `Int` as a flat
    /// ARRAY of alternating keys and values — legal JSON, but an opaque shape
    /// to anything that later reads these files.
    private var layoutsByMode: [String: PaneLayout]

    var id: String { name }

    static let defaultName = "Default"

    subscript(mode: EditorMode) -> PaneLayout {
        get { layoutsByMode[mode.rawValue] ?? .default }
        set { layoutsByMode[mode.rawValue] = newValue }
    }

    init(name: String, layoutsByMode: [String: PaneLayout]) {
        self.name = name
        self.layoutsByMode = layoutsByMode
    }

    /// A workspace giving every mode the same `layout`.
    static func uniform(name: String, layout: PaneLayout) -> Self {
        Self(
            name: name,
            layoutsByMode: Dictionary(
                uniqueKeysWithValues: EditorMode.allCases.map { ($0.rawValue, layout) }
            )
        )
    }

    /// The built-in preset. It can be neither renamed, overwritten nor deleted.
    static let `default` = Self.uniform(name: defaultName, layout: .default)

    var isBuiltIn: Bool { name == Self.defaultName }
}
