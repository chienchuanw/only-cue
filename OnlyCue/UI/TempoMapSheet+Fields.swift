import SwiftUI

/// The editable row controls of `TempoMapSheet` — a labelled numeric field plus
/// the `Binding`s that commit each edit through `CueCommands.updateTempoSection`.
/// Split out of `TempoMapSheet.swift` to keep that view under the
/// `type_body_length` cap.
extension TempoMapSheet {

    /// A trailing-aligned numeric `TextField` with a small unit suffix.
    func field(_ title: String, _ value: Binding<Double>, suffix: String) -> some View {
        HStack(spacing: 2) {
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            Text(suffix).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// A `Binding` over one of the section's `Double` fields; setting it builds the
    /// edited section via `apply` and commits the whole thing via
    /// `CueCommands.updateTempoSection` (one undo step, no-op if unchanged).
    func binding(
        _ keyPath: KeyPath<TempoSection, Double>,
        of section: TempoSection,
        in item: MediaItem,
        set apply: @escaping (inout TempoSection, Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { section[keyPath: keyPath] },
            set: { newValue in
                var edited = section
                apply(&edited, newValue)
                CueCommands.updateTempoSection(
                    section.id,
                    startSeconds: edited.startSeconds,
                    bpm: edited.bpm,
                    downbeatOffsetSeconds: edited.downbeatOffsetSeconds,
                    item: item.id,
                    document: document,
                    undoManager: undoManager
                )
            }
        )
    }

    func beatsPerBarBinding(_ section: TempoSection, in item: MediaItem) -> Binding<Int> {
        Binding(
            get: { section.beatsPerBar },
            set: {
                CueCommands.updateTempoSection(section.id, beatsPerBar: $0, item: item.id, document: document, undoManager: undoManager)
            }
        )
    }
}
