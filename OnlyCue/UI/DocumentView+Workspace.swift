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

    /// Applies `workspace` to this window, clamping each mode's layout to the
    /// width actually available.
    ///
    /// Clamps a **copy**: the stored preset is never rewritten (spec decision
    /// 8). Rewriting would mean a designer who applies a 400pt-inspector
    /// workspace on a laptop finds it permanently shrunk when they dock again.
    func applyWorkspace(_ workspace: WorkspaceLayout, availableWidth: CGFloat) {
        guard availableWidth > 0 else { return }
        var applied = workspace
        for mode in EditorMode.allCases {
            applied[mode] = workspace[mode].clamped(toAvailableWidth: availableWidth)
        }
        setLiveLayout(applied)
        // The sidebar is an AppKit split view: setting the value in state is
        // not enough, it has to be pushed through the bridge (Task 4).
        let pane = applied[editorMode]
        pendingSidebarWidth = pane.isSidebarCollapsed ? 0 : pane.sidebarWidth
    }

    /// Snapshots this window's current arrangement under `name`.
    func captureCurrentWorkspace(named name: String) -> WorkspaceLayout {
        var snapshot = liveLayout
        snapshot.name = name
        return snapshot
    }
}

/// Hosts every workspace notification receiver plus the two sheets, so
/// `DocumentView.body` gains one modifier rather than eight.
private struct WorkspaceMenuReceiver: ViewModifier {

    let applyWorkspace: (WorkspaceLayout) -> Void
    let captureCurrentWorkspace: (String) -> WorkspaceLayout
    let selectedWorkspaceName: () -> String?

    @ObservedObject private var store = WorkspaceLayoutStore.shared
    @State private var namePrompt: WorkspaceNamePrompt?
    @State private var isManaging = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .workspaceSelected)) { note in
                guard let name = note.object as? String,
                      let preset = store.state.presets.first(where: { $0.name == name })
                else { return }
                store.select(name)
                applyWorkspace(preset)
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceSaveAsRequested)) { _ in
                namePrompt = WorkspaceNamePrompt(kind: .saveAs, initialName: "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceOverwriteRequested)) { _ in
                guard let name = selectedWorkspaceName(), name != WorkspaceLayout.defaultName
                else { return }
                store.overwrite(name: name, with: captureCurrentWorkspace(name))
            }
            .onReceive(NotificationCenter.default.publisher(for: .manageWorkspacesRequested)) { _ in
                isManaging = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceResetRequested)) { _ in
                store.resetToDefault()
                applyWorkspace(.default)
            }
            .sheet(item: $namePrompt) { prompt in
                WorkspaceNameSheet(prompt: prompt) { name in
                    store.save(captureCurrentWorkspace(name))
                }
            }
            .sheet(isPresented: $isManaging) {
                ManageWorkspacesSheet()
            }
    }
}

extension View {
    func workspaceMenuReceiver(
        applyWorkspace: @escaping (WorkspaceLayout) -> Void,
        captureCurrentWorkspace: @escaping (String) -> WorkspaceLayout,
        selectedWorkspaceName: @escaping () -> String?
    ) -> some View {
        modifier(
            WorkspaceMenuReceiver(
                applyWorkspace: applyWorkspace,
                captureCurrentWorkspace: captureCurrentWorkspace,
                selectedWorkspaceName: selectedWorkspaceName
            )
        )
    }

    /// Chains the background-based width measurement and the workspace
    /// notification receivers onto a `DocumentView`. Extracted here so
    /// `DocumentView.swift` stays under SwiftLint's `file_length` cap.
    ///
    /// Uses `.background { GeometryReader { ... } }` — the strictly safer form
    /// (spec decision 8 / #617): a background GeometryReader has zero layout
    /// impact; it does **not** propagate to the parent as a greedy fill.
    func workspaceHosted(for view: DocumentView) -> some View {
        // Capture the bindings / closures once so the trailing closures below
        // hold lightweight value types only.
        let widthBinding = Binding<CGFloat>(
            get: { view.availableWindowWidth },
            set: { view.availableWindowWidth = $0 }
        )
        return self
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.width, initial: true) { _, newValue in
                            widthBinding.wrappedValue = newValue
                        }
                }
            }
            .workspaceMenuReceiver(
                applyWorkspace: { view.applyWorkspace($0, availableWidth: view.availableWindowWidth) },
                captureCurrentWorkspace: { view.captureCurrentWorkspace(named: $0) },
                selectedWorkspaceName: { WorkspaceLayoutStore.shared.state.selectedName }
            )
    }
}
