import SwiftUI

/// "Send to grandMA2…" sheet (#683): target slots + cue-type filter
/// (pre-filled from the clip's saved `ma2PushTarget`), pre-flight errors,
/// an explicit overwrite confirmation, then the runner's step list.
struct MA2PushSheet: View {

    let item: MediaItem
    let cuePointTypes: [CuePointType]
    let framerate: SMPTEFramerate
    let showfile: String
    let onSaveTarget: (MA2PushTarget) -> Void
    let onDismiss: () -> Void

    @AppStorage(MA2ConnectionSettings.hostKey) private var host = ""
    @AppStorage(MA2ConnectionSettings.portKey) private var port = MA2ConnectionSettings.defaultPort

    @State private var sequenceSlot: Int
    @State private var timecodeSlot: Int
    @State private var executorPage: Int
    @State private var executorNumber: Int
    @State private var timecodeCommand: MA2TimecodeCommand
    @State private var includedTypeIDs: Set<UUID>
    @State private var sequenceName: String

    @State private var preflightIssues: [MA2PushPreflight.Issue] = []
    @State private var confirmingCommands: [String]?
    @State private var runner: MA2PushRunner?
    @State private var pushTask: Task<Void, Never>?

    init(
        item: MediaItem,
        cuePointTypes: [CuePointType],
        framerate: SMPTEFramerate,
        showfile: String,
        onSaveTarget: @escaping (MA2PushTarget) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.cuePointTypes = cuePointTypes
        self.framerate = framerate
        self.showfile = showfile
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
            Text("Send to grandMA2")
                .font(.title2)
                .accessibilityIdentifier("ma2PushSheetTitle")
            Text("\(item.resolvedName) → \(host.isEmpty ? "no console configured" : host)")
                .font(.callout)
                .foregroundStyle(DS.Color.textSecondary)

            if let runner {
                MA2PushProgressList(runner: runner)
            } else if let confirmingCommands {
                confirmationCard(for: confirmingCommands)
            } else {
                targetCard
                typesCard
                preflightCard
            }

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
        .accessibilityIdentifier("ma2PushSheet")
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            if let runner {
                Spacer()
                if runner.isRunning {
                    Button("Cancel") { pushTask?.cancel() }
                        .accessibilityIdentifier("ma2CancelPushButton")
                } else {
                    Button("Close") { onDismiss() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("ma2CloseButton")
                }
            } else if confirmingCommands != nil {
                Button("Back") { confirmingCommands = nil }
                Spacer()
                Button("Replace and Push") { push() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("ma2ConfirmPushButton")
            } else {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Push…") { prepare() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.isEmpty || !isConfigurationValid)
                    .accessibilityIdentifier("ma2PushButton")
            }
        }
    }

    /// Slots/pages/executors must be 1-based and the port a real TCP port —
    /// `UInt16(port)` would trap on out-of-range settings values.
    private var isConfigurationValid: Bool {
        currentTarget.isValid && UInt16(exactly: port).map { $0 > 0 } == true
    }

    private func prepare() {
        let target = currentTarget
        switch MA2PushRequestBuilder.commandOutcome(item: item, target: target, framerate: framerate) {
        case .blocked(let issues):
            preflightIssues = issues
        case .ready(let commands):
            // Persist the target (undoably) only for a push that can proceed —
            // a blocked attempt should not dirty the document.
            onSaveTarget(target)
            preflightIssues = []
            confirmingCommands = commands
        }
    }

    private func push() {
        guard let commands = confirmingCommands, let portValue = UInt16(exactly: port), portValue > 0 else { return }
        let client = MA2TelnetClient(configuration: .init(host: host, port: portValue))
        let runner = MA2PushRunner(transport: client)
        self.runner = runner
        confirmingCommands = nil
        pushTask = Task {
            // Credentials are grandMA2's fixed defaults (#690) — nothing to read.
            await runner.run(
                commands: commands,
                host: host,
                username: MA2ConnectionSettings.username,
                password: MA2ConnectionSettings.password
            )
        }
    }

    private func typeBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { includedTypeIDs.contains(id) },
            set: { include in
                if include { includedTypeIDs.insert(id) } else { includedTypeIDs.remove(id) }
            }
        )
    }

    static func describe(_ issue: MA2PushPreflight.Issue) -> String {
        switch issue {
        case .noCues:
            return "No cues match the current filter."
        case .unnumbered(let cues):
            return "\(cues.count) cue(s) have no cue number."
        case .duplicateNumber(let number, let cues):
            return "Cue number \(FadeTime.formatNumber(number)) is used by \(cues.count) cues."
        }
    }
}

// MARK: - Cards
// (An extension keeps the main type body under SwiftLint's length limit.)

private extension MA2PushSheet {

    var targetCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Target").dsSectionHeader()
            HStack {
                Text("Sequence name")
                TextField("English name", text: $sequenceName)
                    .accessibilityIdentifier("ma2SequenceNameField")
            }
            Grid(alignment: .leading, horizontalSpacing: DS.Space.md, verticalSpacing: DS.Space.xs) {
                GridRow {
                    Text("Sequence slot")
                    TextField("", value: $sequenceSlot, format: .number.grouping(.never))
                        .frame(width: 70)
                        .accessibilityIdentifier("ma2SequenceSlotField")
                }
                GridRow {
                    Text("Executor (page.exec)")
                    HStack(spacing: 2) {
                        TextField("", value: $executorPage, format: .number.grouping(.never))
                            .frame(width: 40)
                            .accessibilityIdentifier("ma2ExecutorPageField")
                        Text(".")
                        TextField("", value: $executorNumber, format: .number.grouping(.never))
                            .frame(width: 40)
                            .accessibilityIdentifier("ma2ExecutorNumberField")
                    }
                }
            }
            // `timecodeSlot` / `timecodeCommand` are not shown here — Approach A
            // (per-cue Trig=Timecode) never uses them. They stay in `currentTarget`
            // (seeded from the saved target) so the plugin export keeps its values.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var typesCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Filter by Type").dsSectionHeader()
            Text("Leave all unchecked to push every cue.")
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(cuePointTypes) { type in
                        Toggle(type.name, isOn: typeBinding(for: type.id))
                            .accessibilityIdentifier("ma2TypeRow.\(type.id.uuidString)")
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
                    Label(Self.describe(issue), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                        .font(.callout)
                }
            }
            .accessibilityIdentifier("ma2PreflightIssues")
        }
    }

    private func confirmationCard(for commands: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label(
                "This replaces Sequence \(sequenceSlot) on the console. "
                + "Existing contents of that slot are deleted.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.yellow)
            Text("\(commands.count) commands over telnet.")
                .font(.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityIdentifier("ma2OverwriteConfirmation")
    }
}

/// The runner's step list: one row per upload / telnet command.
private struct MA2PushProgressList: View {
    let runner: MA2PushRunner

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(runner.steps) { step in
                        HStack(spacing: DS.Space.sm) {
                            stepIcon(step.state)
                            Text(step.title)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            if let failure = runner.failureMessage {
                Label(failure, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ma2PushFailureMessage")
            } else if runner.didSucceed {
                Label("Push complete.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("ma2PushSuccessMessage")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityIdentifier("ma2PushProgress")
    }

    @ViewBuilder
    private func stepIcon(_ state: MA2PushRunner.StepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
