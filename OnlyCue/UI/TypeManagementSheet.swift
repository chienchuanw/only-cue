import SwiftUI

struct TypeManagementSheet: View {

    @ObservedObject var document: CueListDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var pendingDeletion: TypeDeletionPlan?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 500, minHeight: 320)
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
                        cueCount: document.model.cueCount(forTypeID: type.id),
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
        let palette = CuePointType.defaultPalette
        let newType = CuePointType(
            id: UUID(),
            name: "Type \(nextIndex + 1)",
            colorHex: palette[nextIndex % palette.count]
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
    let cueCount: Int
    let canDelete: Bool
    var onRename: (String) -> Void
    var onRecolor: (String) -> Void
    var onSetHotkey: (Int?) -> Void
    var onRequestDelete: () -> Void

    @State private var nameDraft = ""
    @State private var isEditingName = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            colorCapsule

            if isEditingName {
                TextField("Type name", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onAppear { nameFocused = true }
                    .onChange(of: nameFocused) { wasFocused, isFocused in
                        if wasFocused && !isFocused { commitName() }
                    }
                    .accessibilityIdentifier("typeName-\(type.id.uuidString)")
            } else {
                Text(type.name)
                    .font(DS.Text.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginRename() }
                    .accessibilityIdentifier("typeName-\(type.id.uuidString)")
            }

            // Audit §10.1: count badge — pluralised, monospaced digit so
            // a column of rows aligns numerically.
            Text("\(cueCount)")
                .font(DS.Text.label.monospacedDigit())
                .foregroundStyle(DS.Color.textTertiary)
                .frame(minWidth: 24, alignment: .trailing)
                .accessibilityLabel(cueCount == 1 ? "1 cue" : "\(cueCount) cues")
                .accessibilityIdentifier("typeCount-\(type.id.uuidString)")

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

    // Audit §10.5: large rounded capsule replaces the small ColorPicker
    // chip. The capsule itself is the affordance — clicking opens a system
    // color popover via the underlying ColorPicker, but the rendered shape
    // is now sized to match Figma's visual weight (~40×16 pt).
    @ViewBuilder
    private var colorCapsule: some View {
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
        .frame(width: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: type.colorHex) ?? .accentColor)
                .frame(width: 40, height: 16)
                .allowsHitTesting(false)
        )
        .accessibilityIdentifier("typeColor-\(type.id.uuidString)")
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
        defer { isEditingName = false }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != type.name else {
            nameDraft = type.name
            return
        }
        onRename(trimmed)
    }

    private func beginRename() {
        nameDraft = type.name
        isEditingName = true
    }
}
