import SwiftUI

/// "Send to grandMA2…" batch sheet (#765): pick any subset of the project's songs, give each
/// a unique sequence slot and an optional executor, apply one global cue-type filter, then
/// push them over one console session. Unnumbered cues are auto-filled (#763) and executors
/// are optional (#764). Replaces the single-song `MA2PushSheet`.
@MainActor
@Observable
final class MA2BatchPushModel: Identifiable {

    nonisolated let id = UUID()

    struct SongInput {
        let itemID: MediaItem.ID
        let name: String
        let cues: [Cue]
        let saved: MA2PushTarget?
    }

    struct Row: Identifiable {
        let itemID: MediaItem.ID
        let name: String
        let cues: [Cue]
        let saved: MA2PushTarget?
        var isSelected: Bool
        var slotText: String
        var executorText: String
        var id: MediaItem.ID { itemID }

        var cueCount: Int { cues.count }
        var unnumberedCount: Int { cues.filter { $0.cueNumber == nil }.count }
    }

    var rows: [Row]
    var includedTypeIDs: Set<UUID>
    var runner: MA2BatchPushRunner?
    /// The pre-checked song the sheet scrolls into view on open (#765).
    let scrollTarget: MediaItem.ID?

    init(songs: [SongInput], activeItemID: MediaItem.ID?, preselect: MediaItem.ID?) {
        var usedSlots = Set(songs.compactMap { $0.saved?.sequenceSlot })
        var nextSlot = 1
        func allocateSlot() -> Int {
            while usedSlots.contains(nextSlot) { nextSlot += 1 }
            usedSlots.insert(nextSlot)
            return nextSlot
        }
        let checked = preselect ?? activeItemID
        scrollTarget = checked
        rows = songs.map { song in
            let slot = song.saved?.sequenceSlot ?? allocateSlot()
            return Row(
                itemID: song.itemID,
                name: song.name,
                cues: song.cues,
                saved: song.saved,
                isSelected: song.itemID == checked,
                slotText: String(slot),
                executorText: MA2ExecutorField.text(page: song.saved?.executorPage, number: song.saved?.executorNumber)
            )
        }
        includedTypeIDs = []
    }

    var selectedRows: [Row] { rows.filter(\.isSelected) }

    func target(for row: Row) -> MA2PushTarget {
        MA2PushTarget(
            sequenceSlot: Int(row.slotText) ?? 0,
            timecodeSlot: row.saved?.timecodeSlot ?? 1,
            executorPage: MA2ExecutorField.parse(row.executorText)?.page,
            executorNumber: MA2ExecutorField.parse(row.executorText)?.number,
            timecodeCommand: row.saved?.timecodeCommand ?? .goto,
            includedTypeIDs: includedTypeIDs,
            sequenceName: row.saved?.sequenceName
        )
    }

    var preflight: MA2BatchPreflight.Result {
        MA2BatchPreflight.validate(selectedRows.map { row in
            MA2BatchPreflight.Song(
                itemID: row.itemID,
                cues: row.cues,
                includedTypeIDs: includedTypeIDs,
                target: target(for: row)
            )
        })
    }

    /// Every selected song must have a structurally valid target and the batch pre-flight
    /// must be clear (all-or-nothing).
    var canPush: Bool {
        !selectedRows.isEmpty
            && selectedRows.allSatisfy { target(for: $0).isValid }
            && preflight.isClear
    }
}

struct MA2BatchPushSheet: View {

    @State var model: MA2BatchPushModel
    let document: CueListDocument
    let undoManager: UndoManager?
    let cuePointTypes: [CuePointType]
    let framerate: SMPTEFramerate
    let onDismiss: () -> Void

    @AppStorage(MA2ConnectionSettings.hostKey) private var host = ""
    @AppStorage(MA2ConnectionSettings.portKey) private var port = MA2ConnectionSettings.defaultPort
    @State private var pushTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            header
            if let runner = model.runner {
                MA2BatchProgressList(runner: runner)
            } else {
                songsSection
                filterSection
                preflightBanner
            }
            Spacer(minLength: DS.Space.sm)
            actionRow
        }
        .padding(DS.Space.xl)
        .frame(minWidth: 640, idealWidth: 640, minHeight: 460)
        .background(DS.Color.panel)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityIdentifier("ma2BatchSheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Send to grandMA2")
                .font(.title2)
                .accessibilityIdentifier("ma2BatchSheetTitle")
            Text("\(model.selectedRows.count) of \(model.rows.count) songs selected  ·  "
                 + (host.isEmpty ? "no console configured" : host))
                .font(.callout)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    // MARK: Songs

    @ViewBuilder
    private var songsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("SONGS").dsSectionHeader()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DS.Space.xs) {
                        ForEach($model.rows) { $row in
                            songRow($row).id(row.itemID)
                        }
                    }
                }
                .frame(maxHeight: 220)
                .onAppear {
                    // Right-click / active entry pre-checks a song — scroll it into view (#765).
                    if let target = model.scrollTarget {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    private func songRow(_ row: Binding<MA2BatchPushModel.Row>) -> some View {
        HStack(spacing: DS.Space.md) {
            Toggle("", isOn: row.isSelected)
                .labelsHidden()
                .accessibilityIdentifier("ma2BatchRowToggle.\(row.wrappedValue.itemID.uuidString)")
            VStack(alignment: .leading, spacing: 1) {
                Text(row.wrappedValue.name)
                    .foregroundStyle(row.wrappedValue.isSelected ? DS.Color.textPrimary : DS.Color.textSecondary)
                Text(statusText(row.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(row.wrappedValue.unnumberedCount > 0 ? .yellow : DS.Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", text: row.slotText)
                .frame(width: 56)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ma2BatchSlot.\(row.wrappedValue.itemID.uuidString)")
            TextField("—", text: row.executorText)
                .frame(width: 72)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ma2BatchExecutor.\(row.wrappedValue.itemID.uuidString)")
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.sm)
        .opacity(row.wrappedValue.isSelected ? 1 : 0.55)
        .accessibilityIdentifier("ma2BatchRow.\(row.wrappedValue.itemID.uuidString)")
    }

    private func statusText(_ row: MA2BatchPushModel.Row) -> String {
        var text = "\(row.cueCount) cue\(row.cueCount == 1 ? "" : "s")"
        if row.unnumberedCount > 0 {
            text += " · \(row.unnumberedCount) will be auto-numbered"
        }
        return text
    }

    // MARK: Filter

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("FILTER BY TYPE").dsSectionHeader()
            Text("Applies to all selected songs. Leave all unchecked to push every cue.")
                .font(.caption)
                .foregroundStyle(DS.Color.textTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: DS.Space.sm)], alignment: .leading) {
                ForEach(cuePointTypes) { type in
                    Toggle(type.name, isOn: typeBinding(type.id))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("ma2BatchType.\(type.id.uuidString)")
                }
            }
        }
    }

    private func typeBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { model.includedTypeIDs.contains(id) },
            set: { include in
                if include { model.includedTypeIDs.insert(id) } else { model.includedTypeIDs.remove(id) }
            }
        )
    }

    // MARK: Preflight

    @ViewBuilder
    private var preflightBanner: some View {
        let issues = preflightMessages
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(Array(issues.enumerated()), id: \.offset) { _, message in
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .accessibilityIdentifier("ma2BatchPreflight")
        }
    }

    private var preflightMessages: [String] {
        let result = model.preflight
        var messages: [String] = result.cross.map { issue in
            switch issue {
            case let .duplicateSequenceSlot(slot, itemIDs):
                return "Sequence slot \(slot) is used by \(itemIDs.count) songs — give each a unique slot."
            case let .duplicateExecutor(page, number, itemIDs):
                return "Executor \(page).\(number) is used by \(itemIDs.count) songs — give each a unique executor."
            }
        }
        for song in result.perSong {
            let name = model.rows.first { $0.itemID == song.itemID }?.name ?? "A song"
            messages += song.issues.map { "\(name): \(MA2PushSheet.describe($0))" }
        }
        return messages
    }

    // MARK: Actions

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            if let runner = model.runner {
                summaryLabel(runner)
                Spacer()
                if runner.isRunning {
                    Button("Cancel") { pushTask?.cancel() }
                        .accessibilityIdentifier("ma2BatchCancelButton")
                } else {
                    Button("Close") { onDismiss() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("ma2BatchCloseButton")
                }
            } else {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Push \(model.selectedRows.count) song\(model.selectedRows.count == 1 ? "" : "s")…") { push() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.isEmpty || !model.canPush || !portValid)
                    .accessibilityIdentifier("ma2BatchPushButton")
            }
        }
    }

    private func summaryLabel(_ runner: MA2BatchPushRunner) -> some View {
        Text("\(runner.succeededCount) done · \(runner.failedCount) failed")
            .font(.callout)
            .foregroundStyle(DS.Color.textSecondary)
            .accessibilityIdentifier("ma2BatchSummary")
    }

    private var portValid: Bool { UInt16(exactly: port).map { $0 > 0 } == true }

    private func push() {
        guard let portValue = UInt16(exactly: port), portValue > 0 else { return }
        let rows = model.selectedRows
        let selections = rows.map { MA2BatchPushPlan.Selection(itemID: $0.itemID, target: model.target(for: $0)) }
        let targets = Dictionary(uniqueKeysWithValues: rows.map { ($0.itemID, model.target(for: $0)) })
        // Auto-fill each selected song's cue numbers (undoable) so its commands can be built.
        // Targets are persisted only for songs that reach the console (see `persistTargets`).
        let songs = MA2BatchPushPlan.build(selections, document: document, undoManager: undoManager, framerate: framerate)
        let runner = MA2BatchPushRunner(transport: MA2TelnetClient(configuration: .init(host: host, port: portValue)))
        model.runner = runner
        pushTask = Task {
            await runner.run(
                songs: songs,
                host: host,
                username: MA2ConnectionSettings.username,
                password: MA2ConnectionSettings.password
            )
            persistTargets(for: runner, targets: targets)
        }
    }

    /// Persist the push target only for songs that actually reached the console (#765) — a
    /// re-push should remember a confirmed configuration, not a failed or never-sent attempt.
    private func persistTargets(for runner: MA2BatchPushRunner, targets: [MediaItem.ID: MA2PushTarget]) {
        let succeeded = runner.songs.filter { $0.state == .done }
        guard !succeeded.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        for song in succeeded {
            if let target = targets[song.itemID] {
                CueCommands.setMA2PushTarget(target, itemID: song.itemID, document: document, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Set grandMA2 Targets")
        undoManager?.endUndoGrouping()
    }
}

/// Per-song progress rows for the batch push, mirroring the runner's state.
private struct MA2BatchProgressList: View {
    let runner: MA2BatchPushRunner

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("PROGRESS").dsSectionHeader()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(runner.songs) { song in
                        HStack(spacing: DS.Space.sm) {
                            icon(song.state)
                            Text(song.name).lineLimit(1)
                            Spacer()
                            Text(note(song.state))
                                .font(.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                        .accessibilityIdentifier("ma2BatchProgressRow.\(song.itemID.uuidString)")
                    }
                }
            }
            .frame(maxHeight: 240)
            if let fatal = runner.fatalMessage {
                Label(fatal, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ma2BatchFatalMessage")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityIdentifier("ma2BatchProgress")
    }

    @ViewBuilder
    private func icon(_ state: MA2BatchPushRunner.SongState) -> some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func note(_ state: MA2BatchPushRunner.SongState) -> String {
        switch state {
        case .pending: return "queued"
        case .running: return "pushing…"
        case .done: return "done"
        case let .failed(message): return message
        }
    }
}
