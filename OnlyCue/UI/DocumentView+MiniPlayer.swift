import AppKit
import SwiftUI

/// Mini Player (#748) wiring for a document window, split out to keep
/// `DocumentView` under the SwiftLint `file_length` cap. Mirrors the
/// `workspaceHosted(for:)` pattern: a single `.miniPlayerHosted(for: self)`
/// modifier owns the toggle command, live context sync, title updates, and
/// teardown. The panel shares this window's `PlayerEngine` + document, so it is
/// always in sync (spec: docs/superpowers/specs/2026-08-16-miniplay-design.md).
extension View {
    func miniPlayerHosted(for view: DocumentView) -> some View {
        let frontmost = Binding<Bool>(
            get: { view.isMiniFrontmost },
            set: { view.isMiniFrontmost = $0 }
        )
        return self
            .frontmostWindowGate(isFrontmost: frontmost)
            .onReceive(NotificationCenter.default.publisher(for: .toggleMiniPlayerRequested)) { _ in
                guard view.miniHandlesNotifications else { return }
                view.toggleMiniPlayer()
            }
            .onChange(of: view.editorMode) { _, _ in view.syncMiniPlayerContext() }
            .onChange(of: view.showGoTypeIDRaw) { _, _ in view.syncMiniPlayerContext() }
            .onChange(of: view.document.model.activeItemID) { _, _ in view.updateMiniPlayerTitle() }
            .onAppear {
                view.syncMiniPlayerContext()
                if view.miniPlayerVisible { view.openMiniPlayer() }
            }
            .onDisappear { view.miniController.close() }
    }
}

extension DocumentView {

    private static let miniAutosaveName = "OnlyCue.MiniPlayer"

    /// The panel's window title = the active clip's name (native title bar).
    var miniPlayerTitle: String {
        document.model.activeItem?.resolvedName ?? "Mini Player"
    }

    private var openMiniDocumentWindowCount: Int {
        NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.count
    }

    /// Only the frontmost document window responds to the global toggle command.
    var miniHandlesNotifications: Bool {
        WindowScope.shouldHandle(
            isFrontmost: isMiniFrontmost,
            openWindowCount: openMiniDocumentWindowCount
        )
    }

    private var miniPlayerRoot: MiniPlayerHostView {
        MiniPlayerHostView(engine: engine, document: document, context: miniContext)
    }

    func syncMiniPlayerContext() {
        miniContext.editorMode = editorMode
        miniContext.showGoTypeID = showGoTypeID
    }

    func updateMiniPlayerTitle() {
        miniController.setTitle(miniPlayerTitle)
    }

    func toggleMiniPlayer() {
        syncMiniPlayerContext()
        miniController.toggle(
            rootView: miniPlayerRoot,
            title: miniPlayerTitle,
            autosaveName: Self.miniAutosaveName
        )
        miniPlayerVisible = miniController.isVisible
    }

    func openMiniPlayer() {
        syncMiniPlayerContext()
        miniController.show(
            rootView: miniPlayerRoot,
            title: miniPlayerTitle,
            autosaveName: Self.miniAutosaveName
        )
        miniPlayerVisible = true
    }
}
