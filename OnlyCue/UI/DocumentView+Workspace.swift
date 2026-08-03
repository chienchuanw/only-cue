import SwiftUI

/// Workspace layout helpers for `DocumentView` (#714).
/// Extracted here to keep `DocumentView.swift` within SwiftLint's
/// `file_length` cap.
extension DocumentView {

    /// The window's live arrangement, decoded from scene storage. Falls back to
    /// the store's most-recent layout so a brand-new window inherits how the
    /// last one looked rather than the factory default (spec scope item 7).
    var liveLayout: WorkspaceLayout {
        guard let data = liveLayoutData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(WorkspaceLayout.self, from: data)
        else { return WorkspaceLayoutStore.shared.state.mostRecentLayout }
        return decoded
    }

    /// The current mode's pane widths.
    var currentPaneLayout: PaneLayout { liveLayout[editorMode] }

    /// Mutates the current mode's arrangement and records it as the most recent
    /// layout. Records — never writes back into the selected preset: a preset
    /// is a snapshot, so dragging a divider must leave it byte-identical.
    func updateLiveLayout(_ transform: (inout PaneLayout) -> Void) {
        var workspace = liveLayout
        var pane = workspace[editorMode]
        transform(&pane)
        workspace[editorMode] = pane
        setLiveLayout(workspace)
    }

    func setLiveLayout(_ workspace: WorkspaceLayout) {
        guard let data = try? JSONEncoder().encode(workspace),
              let json = String(data: data, encoding: .utf8)
        else { return }
        liveLayoutData = json
        WorkspaceLayoutStore.shared.recordLiveLayout(workspace)
    }

    /// The sidebar width a preset wants applied, or nil while the user is in
    /// charge. Set for one apply cycle by `applyWorkspace(_:)` (Task 5) and
    /// cleared as soon as the measurement confirms it landed, so a later native
    /// drag is never fought.
    var pendingSidebarWidth: CGFloat? {
        get { pendingSidebarWidthValue < 0 ? nil : pendingSidebarWidthValue }
        nonmutating set { pendingSidebarWidthValue = newValue ?? -1 }
    }

    /// A binding the divider can drive directly.
    var inspectorWidthBinding: Binding<CGFloat> {
        Binding(
            get: { currentPaneLayout.inspectorWidth },
            set: { newValue in updateLiveLayout { $0.inspectorWidth = newValue } }
        )
    }
}
