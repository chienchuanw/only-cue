import SwiftUI
import AppKit

/// "Export grandMA2 plugin…" config sheet (#688): the full target — sequence
/// name/slot, executor, **timecode slot + Go/Goto command** (Approach C builds a
/// real timecode-pool object, so unlike the live push it uses these) — plus the
/// cue-type filter and pre-flight, then Export → an `NSSavePanel` writing the
/// `.lua` + `.xml`. Shares the per-clip `MA2PushTarget` with the live push sheet.
struct MA2PluginExportSheet: View {

    let item: MediaItem
    let cuePointTypes: [CuePointType]
    let framerate: SMPTEFramerate
    let onSaveTarget: (MA2PushTarget) -> Void
    let onDismiss: () -> Void

    @State private var sequenceName: String
    @State private var sequenceSlot: Int
    @State private var timecodeSlot: Int
    @State private var executorPage: Int
    @State private var executorNumber: Int
    @State private var timecodeCommand: MA2TimecodeCommand
    @State private var includedTypeIDs: Set<UUID>
    @State private var preflightIssues: [MA2PushPreflight.Issue] = []
    @State private var writeErrorMessage: String?
    @State private var showingWriteError = false

    init(
        item: MediaItem,
        cuePointTypes: [CuePointType],
        framerate: SMPTEFramerate,
        onSaveTarget: @escaping (MA2PushTarget) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.cuePointTypes = cuePointTypes
        self.framerate = framerate
        self.onSaveTarget = onSaveTarget
        self.onDismiss = onDismiss
        let saved = item.ma2PushTarget ?? MA2PushTarget(
            sequenceSlot: 1,
            timecodeSlot: 1,
            executorPage: 1,
            executorNumber: 1,
            timecodeCommand: .goto,
            includedTypeIDs: []
        )
        _sequenceSlot = State(initialValue: saved.sequenceSlot)
        _timecodeSlot = State(initialValue: saved.timecodeSlot)
        _executorPage = State(initialValue: saved.executorPage)
        _executorNumber = State(initialValue: saved.executorNumber)
        _timecodeCommand = State(initialValue: saved.timecodeCommand)
        _includedTypeIDs = State(initialValue: saved.includedTypeIDs)
        _sequenceName = State(initialValue: saved.sequenceName
            ?? MA2Name.sanitize(item.resolvedName, fallbackSlot: saved.sequenceSlot))
    }

    private var currentTarget: MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: sequenceSlot,
            timecodeSlot: timecodeSlot,
            executorPage: executorPage,
            executorNumber: executorNumber,
            timecodeCommand: timecodeCommand,
            includedTypeIDs: includedTypeIDs,
            sequenceName: sequenceName.isEmpty ? nil : sequenceName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("Export grandMA2 plugin")
                .font(.title2)
                .accessibilityIdentifier("ma2PluginExportSheetTitle")
            Text("\(item.resolvedName) → a .lua + .xml plugin you import and run on the console")
                .font(.callout)
                .foregroundStyle(DS.Color.textSecondary)

            targetCard
            typesCard
            preflightCard

            Spacer(minLength: DS.Space.sm)
            actionRow
        }
        .padding(DS.Space.xl)
        .frame(minWidth: 480, idealWidth: 480, minHeight: 380)
        .background(DS.Color.panel)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityIdentifier("ma2PluginExportSheet")
        .alert("Plugin export failed", isPresented: $showingWriteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(writeErrorMessage ?? "")
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Cancel") { onDismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Export…") { export() }
                .keyboardShortcut(.defaultAction)
                .disabled(!currentTarget.isValid)
                .accessibilityIdentifier("ma2PluginExportButton")
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Target").dsSectionHeader()
            HStack {
                Text("Sequence name")
                TextField("English name", text: $sequenceName)
                    .accessibilityIdentifier("ma2PluginSequenceNameField")
            }
            Grid(alignment: .leading, horizontalSpacing: DS.Space.md, verticalSpacing: DS.Space.xs) {
                GridRow {
                    Text("Sequence slot")
                    TextField("", value: $sequenceSlot, format: .number.grouping(.never))
                        .frame(width: 70)
                        .accessibilityIdentifier("ma2PluginSequenceSlotField")
                    Text("Timecode slot")
                    TextField("", value: $timecodeSlot, format: .number.grouping(.never))
                        .frame(width: 70)
                        .accessibilityIdentifier("ma2PluginTimecodeSlotField")
                }
                GridRow {
                    Text("Executor (page.exec)")
                    HStack(spacing: 2) {
                        TextField("", value: $executorPage, format: .number.grouping(.never))
                            .frame(width: 40)
                            .accessibilityIdentifier("ma2PluginExecutorPageField")
                        Text(".")
                        TextField("", value: $executorNumber, format: .number.grouping(.never))
                            .frame(width: 40)
                            .accessibilityIdentifier("ma2PluginExecutorNumberField")
                    }
                    Text("TC command")
                    Picker("", selection: $timecodeCommand) {
                        Text("Goto").tag(MA2TimecodeCommand.goto)
                        Text("Go").tag(MA2TimecodeCommand.go)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .accessibilityIdentifier("ma2PluginTimecodeCommandPicker")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var typesCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Filter by Type").dsSectionHeader()
            Text("Leave all unchecked to export every cue.")
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(cuePointTypes) { type in
                        Toggle(type.name, isOn: typeBinding(for: type.id))
                            .accessibilityIdentifier("ma2PluginTypeRow.\(type.id.uuidString)")
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    @ViewBuilder
    private var preflightCard: some View {
        if !preflightIssues.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(Array(preflightIssues.enumerated()), id: \.offset) { _, issue in
                    Label(MA2PushSheet.describe(issue), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                        .font(.callout)
                }
            }
            .accessibilityIdentifier("ma2PluginPreflightIssues")
        }
    }

    private func typeBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { includedTypeIDs.contains(id) },
            set: { isOn in
                if isOn { includedTypeIDs.insert(id) } else { includedTypeIDs.remove(id) }
            }
        )
    }

    private func export() {
        let target = currentTarget
        let datetime = ISO8601DateFormatter().string(from: Date())
        switch MA2PushRequestBuilder.pluginOutcome(
            item: item, target: target, framerate: framerate, datetime: datetime
        ) {
        case .blocked(let issues):
            preflightIssues = issues
        case .ready(let bundle):
            onSaveTarget(target)
            preflightIssues = []
            save(bundle)
        }
    }

    private func save(_ bundle: MA2PluginBundle) {
        let panel = NSSavePanel()
        panel.title = "Export grandMA2 plugin"
        panel.nameFieldStringValue = bundle.manifestFilename
        panel.prompt = "Export"
        panel.message = "Both the .xml and its _PLUGIN.lua are written next to each other."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MA2PluginWriter.write(bundle, toDirectory: url.deletingLastPathComponent())
            onDismiss()
        } catch {
            writeErrorMessage = error.localizedDescription
            showingWriteError = true
        }
    }
}
