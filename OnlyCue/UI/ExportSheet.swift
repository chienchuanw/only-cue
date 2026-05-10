import SwiftUI

/// User-facing export configuration sheet — format picker + per-Type filter.
/// Empty Type selection (no checkboxes on) means "export all" per the
/// `CueExportFilter` contract; the UI shows a hint to that effect so the
/// user doesn't think they have to tick everything.
struct ExportSheet: View {

    let cuePointTypes: [CuePointType]
    @Binding var target: ExportTarget
    @Binding var selectedTypeIDs: Set<UUID>

    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Cues")
                .font(.title2)
                .accessibilityIdentifier("exportSheetTitle")

            formatRow
            Divider()
            typesSection

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .accessibilityIdentifier("exportCancel")
                    .keyboardShortcut(.cancelAction)
                Button("Export…", action: onConfirm)
                    .accessibilityIdentifier("exportConfirm")
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320)
        .accessibilityIdentifier("exportSheet")
    }

    private var formatRow: some View {
        HStack {
            Text("Format")
                .frame(width: 80, alignment: .leading)
            Picker("Format", selection: $target) {
                ForEach(ExportTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("exportFormatPicker")
        }
    }

    @ViewBuilder
    private var typesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter by Type")
                .font(.headline)
            Text("Leave all unchecked to export every cue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if cuePointTypes.isEmpty {
                Text("No types in this project.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(cuePointTypes) { type in
                            Toggle(type.name, isOn: binding(for: type.id))
                                .accessibilityIdentifier("exportTypeRow.\(type.id.uuidString)")
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private func binding(for typeID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTypeIDs.contains(typeID) },
            set: { isOn in
                if isOn {
                    selectedTypeIDs.insert(typeID)
                } else {
                    selectedTypeIDs.remove(typeID)
                }
            }
        )
    }
}
