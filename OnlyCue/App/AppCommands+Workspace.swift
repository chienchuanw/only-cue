import SwiftUI

/// View ▸ Workspace submenu helpers for `AppCommands` (#714). Extracted here
/// so `AppCommands.swift` stays under SwiftLint's `file_length` cap, mirroring
/// the `DocumentView+Workspace.swift` split.
extension AppCommands {

    /// The View ▸ Workspace submenu. Kept in a `private extension` of the
    /// outer struct's file so `body` stays inside SwiftLint's
    /// `type_body_length` cap — same pattern as `playbackModeItem`.
    @ViewBuilder var workspaceMenu: some View {
        Menu("Workspace") {
            ForEach(workspaceStore.state.presets) { preset in
                Button {
                    NotificationCenter.default.post(
                        name: .workspaceSelected,
                        object: preset.name
                    )
                } label: {
                    // The leading-checkmark pattern used by Auto-Scroll
                    // Waveform (#532) — the macOS-standard affordance for
                    // "this one is active". Note XCUITest cannot read the
                    // checkmark, so the UI test only asserts presence.
                    if workspaceStore.state.selectedName == preset.name {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }

            Divider()

            Button("Save Current Layout As…") {
                NotificationCenter.default.post(name: .workspaceSaveAsRequested, object: nil)
            }

            Button(overwriteTitle) {
                NotificationCenter.default.post(name: .workspaceOverwriteRequested, object: nil)
            }
            .disabled(!canOverwriteSelectedWorkspace)

            Button("Manage Workspaces…") {
                NotificationCenter.default.post(name: .manageWorkspacesRequested, object: nil)
            }

            Divider()

            Button("Reset to Default") {
                NotificationCenter.default.post(name: .workspaceResetRequested, object: nil)
            }
        }
        .accessibilityIdentifier("workspaceMenu")
    }

    /// `Overwrite "Focus"` when a user preset is selected; a static title
    /// otherwise, since a disabled item with a dangling quote reads as a bug.
    var overwriteTitle: String {
        guard let name = workspaceStore.state.selectedName,
              name != WorkspaceLayout.defaultName
        else { return "Overwrite Workspace" }
        return "Overwrite \u{201C}\(name)\u{201D}"
    }

    /// The built-in Default can never be overwritten (spec scope item 6).
    var canOverwriteSelectedWorkspace: Bool {
        guard let name = workspaceStore.state.selectedName else { return false }
        return name != WorkspaceLayout.defaultName
    }
}
