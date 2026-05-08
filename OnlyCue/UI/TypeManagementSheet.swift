import SwiftUI

struct TypeManagementSheet: View {

    @ObservedObject var document: CueListDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var pendingDeletion: TypeDeletionPlan?

    private static let defaultPalette: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD93D", "#6BCB77",
        "#4ECDC4", "#4D96FF", "#9D7EE0", "#FF6FB5"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 320)
        .accessibilityIdentifier("typeManagementSheet")
        .confirmationDialog(
            confirmTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { plan in
            Button("Delete", role: .destructive) { performDelete(plan) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { plan in
            Text(confirmMessage(for: plan))
        }
    }

    private var header: some View {
        HStack {
            Text("Manage Types")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(document.model.cuePointTypes) { type in
                    TypeManagementRow(
                        type: type,
                        canDelete: document.model.cuePointTypes.count > 1,
                        onRename: { rename(type.id, to: $0) },
                        onRecolor: { recolor(type.id, to: $0) },
                        onSetHotkey: { setHotkey(type.id, to: $0) },
                        onRequestDelete: { requestDelete(type.id) }
                    )
                    Divider()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: addType) {
                Label("Add Type", systemImage: "plus")
            }
            .accessibilityIdentifier("addTypeButton")

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func rename(_ id: CuePointType.ID, to newName: String) {
        CueCommands.setCuePointTypeName(id: id, to: newName, document: document, undoManager: undoManager)
    }

    private func recolor(_ id: CuePointType.ID, to newColor: String) {
        CueCommands.setCuePointTypeColor(id: id, to: newColor, document: document, undoManager: undoManager)
    }

    private func setHotkey(_ id: CuePointType.ID, to newKey: Int?) {
        CueCommands.setCuePointTypeHotkey(id: id, to: newKey, document: document, undoManager: undoManager)
    }

    private func addType() {
        let nextIndex = document.model.cuePointTypes.count
        let newType = CuePointType(
            id: UUID(),
            name: "Type \(nextIndex + 1)",
            colorHex: Self.defaultPalette[nextIndex % Self.defaultPalette.count]
        )
        CueCommands.addCuePointType(newType, document: document, undoManager: undoManager)
    }

    private func requestDelete(_ id: CuePointType.ID) {
        guard let plan = TypeDeletionPlan.make(forTypeID: id, in: document.model) else { return }
        if plan.referencedCueCount == 0 {
            performDelete(plan)
        } else {
            pendingDeletion = plan
        }
    }

    private func performDelete(_ plan: TypeDeletionPlan) {
        CueCommands.removeCuePointType(
            id: plan.typeID,
            reassignTo: plan.reassignTargetID,
            document: document,
            undoManager: undoManager
        )
        pendingDeletion = nil
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var confirmTitle: String {
        guard let plan = pendingDeletion else { return "" }
        return "Delete \"\(plan.typeName)\"?"
    }

    private func confirmMessage(for plan: TypeDeletionPlan) -> String {
        let cuesNoun = plan.referencedCueCount == 1 ? "cue" : "cues"
        return "\(plan.referencedCueCount) \(cuesNoun) will be moved to \"\(plan.reassignTargetName)\"."
    }
}

struct TypeManagementRow: View {

    let type: CuePointType
    let canDelete: Bool
    var onRename: (String) -> Void
    var onRecolor: (String) -> Void
    var onSetHotkey: (Int?) -> Void
    var onRequestDelete: () -> Void

    @State private var nameDraft = ""
    @State private var colorBinding: Color = .accentColor
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: type.colorHex) ?? .accentColor },
                    set: { newColor in
                        if let hex = newColor.toHex(), hex != type.colorHex {
                            onRecolor(hex)
                        }
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 36)

            TextField("Type name", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { commitName() }
                .onAppear { nameDraft = type.name }
                .onChange(of: type.name) { _, new in if !nameFocused { nameDraft = new } }
                .onChange(of: nameFocused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { commitName() }
                }
                .accessibilityIdentifier("typeName-\(type.id.uuidString)")

            Picker("", selection: hotkeyBinding) {
                Text("—").tag(Int?.none)
                ForEach(0...9, id: \.self) { key in
                    Text("\(key)").tag(Int?.some(key))
                }
            }
            .labelsHidden()
            .frame(width: 64)
            .accessibilityIdentifier("typeHotkey-\(type.id.uuidString)")

            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!canDelete)
            .accessibilityIdentifier("typeDelete-\(type.id.uuidString)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var hotkeyBinding: Binding<Int?> {
        Binding(
            get: { type.hotkey },
            set: { newValue in
                guard newValue != type.hotkey else { return }
                onSetHotkey(newValue)
            }
        )
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != type.name else {
            nameDraft = type.name
            return
        }
        onRename(trimmed)
    }
}
