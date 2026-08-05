import SwiftUI

/// Rename and delete saved workspaces. Figma 493:3017 (420×293): a titled
/// header, a row per preset with a leading checkmark on the selected one and
/// trailing Rename / Delete actions, a hint line, and a Done footer.
///
/// The built-in Default is listed (so the user can see what they are returning
/// to) but its actions are disabled — it can be neither renamed nor deleted
/// (spec scope item 6).
struct ManageWorkspacesSheet: View {

    @ObservedObject private var store = WorkspaceLayoutStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var renamePrompt: WorkspaceNamePrompt?
    @State private var pendingDeletion: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 420, height: 293)
        .accessibilityIdentifier("manageWorkspacesSheet")
        .sheet(item: $renamePrompt) { prompt in
            WorkspaceNameSheet(prompt: prompt) { newName in
                guard case .rename(let oldName) = prompt.kind else { return }
                store.rename(oldName, to: newName)
            }
        }
        .confirmationDialog(
            "Delete \"\(pendingDeletion ?? "")\"?",
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let name = pendingDeletion { store.delete(name) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The workspace is removed. Windows keep their current arrangement.")
        }
    }

    private var header: some View {
        HStack {
            Text("Manage Workspaces")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.state.presets) { preset in
                    row(for: preset)
                    Divider()
                }
            }
        }
    }

    private func row(for preset: WorkspaceLayout) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "checkmark")
                .opacity(store.state.selectedName == preset.name ? 1 : 0)
                .accessibilityHidden(true)

            Text(preset.name)

            Spacer()

            Button("Rename") {
                renamePrompt = WorkspaceNamePrompt(
                    kind: .rename(preset.name),
                    initialName: preset.name
                )
            }
            .disabled(preset.isBuiltIn)

            Button("Delete", role: .destructive) { pendingDeletion = preset.name }
                .disabled(preset.isBuiltIn)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspaceRow.\(preset.name)")
    }

    private var footer: some View {
        HStack {
            Text("The built-in Default workspace can't be renamed or deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}
