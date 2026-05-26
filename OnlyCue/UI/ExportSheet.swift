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
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("Export Cues")
                .font(.title2)
                .accessibilityIdentifier("exportSheetTitle")

            formatCard
            typesCard

            Spacer(minLength: DS.Space.sm)

            actionRow
        }
        .padding(DS.Space.xl)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320)
        .background(DS.Color.panel)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityIdentifier("exportSheet")
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Format").dsSectionHeader()
            Picker("Format", selection: $target) {
                ForEach(ExportTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("exportFormatPicker")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    @ViewBuilder
    private var typesCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Filter by Type").dsSectionHeader()
            Text("Leave all unchecked to export every cue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if cuePointTypes.isEmpty {
                Text("No types in this project.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(cuePointTypes) { type in
                            Toggle(type.name, isOn: binding(for: type.id))
                                .accessibilityIdentifier("exportTypeRow.\(type.id.uuidString)")
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var actionRow: some View {
        VStack(spacing: DS.Space.md) {
            // 1 px border-token divider separating the form from the action row
            // (audit §2.5). Padded back out to span the full sheet width
            // regardless of the parent VStack's spacing.
            Rectangle()
                .fill(DS.Color.border)
                .frame(height: 1)
                .padding(.horizontal, -DS.Space.xl)
                .accessibilityIdentifier("exportActionRowDivider")

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
