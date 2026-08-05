import SwiftUI

/// Why a workspace name cannot be used.
enum WorkspaceNameProblem: Equatable {
    case empty
    case reserved
    case duplicate

    var message: String {
        switch self {
        case .empty: "Enter a name."
        case .reserved: "\"\(WorkspaceLayout.defaultName)\" is reserved for the built-in workspace."
        case .duplicate: "A workspace with that name already exists."
        }
    }
}

/// Pure name rules, so the sheet holds no logic worth testing.
enum WorkspaceNameValidator {

    /// - Parameter currentName: the name being renamed *from*, which is allowed
    ///   to collide with itself — otherwise opening Rename and pressing Save
    ///   without editing would report a duplicate.
    static func validate(
        _ candidate: String,
        existingNames: [String],
        allowing currentName: String?
    ) -> WorkspaceNameProblem? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed != WorkspaceLayout.defaultName else { return .reserved }
        if trimmed == currentName { return nil }
        guard !existingNames.contains(trimmed) else { return .duplicate }
        return nil
    }
}

/// What a `WorkspaceNameSheet` is being opened for.
struct WorkspaceNamePrompt: Identifiable {

    enum Kind: Equatable {
        case saveAs
        /// Renaming the preset currently called this.
        case rename(String)
    }

    let id = UUID()
    let kind: Kind
    let initialName: String

    var title: String {
        switch kind {
        case .saveAs: "Save Workspace"
        case .rename: "Rename Workspace"
        }
    }

    var confirmTitle: String {
        switch kind {
        case .saveAs: "Save"
        case .rename: "Rename"
        }
    }

    /// The name allowed to collide with itself.
    var currentName: String? {
        switch kind {
        case .saveAs: nil
        case .rename(let name): name
        }
    }
}

/// The small name prompt behind Save Current Layout As… and Rename.
///
/// NOTE: no Figma mockup exists for this sheet (#714's set covers Manage
/// Workspaces only). The chrome below is derived from `TypeManagementSheet`
/// and Figma 320:2225 so the two read as one family.
struct WorkspaceNameSheet: View {

    let prompt: WorkspaceNamePrompt
    let onCommit: (String) -> Void

    @ObservedObject private var store = WorkspaceLayoutStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    private var problem: WorkspaceNameProblem? {
        WorkspaceNameValidator.validate(
            name,
            existingNames: store.state.presets.map(\.name),
            allowing: prompt.currentName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(prompt.title)
                .font(.headline)

            TextField("Workspace name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("workspaceNameField")
                .onSubmit { commit() }

            // Reserve the row whether or not there is a problem, so the sheet
            // does not jump height as the user types.
            Text(problem?.message ?? " ")
                .font(.caption)
                .foregroundStyle(problem == nil ? .secondary : Color.red) // semantic: validation error
                .accessibilityIdentifier("workspaceNameProblem")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(prompt.confirmTitle) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
                    .accessibilityIdentifier("workspaceNameCommitButton")
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 360)
        .accessibilityIdentifier("workspaceNameSheet")
        .onAppear { name = prompt.initialName }
    }

    private func commit() {
        guard problem == nil else { return }
        onCommit(name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
