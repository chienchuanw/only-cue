import SwiftUI

/// Modal sheet for editing a single cue's `notes`. Hosted by `CueListPane`
/// via `.sheet(item:)`. Save calls `onSave(draft)`; Cancel calls `onCancel()`.
/// Re-opening the sheet always re-initializes the draft from `initialNotes`,
/// so a dismissed-without-save sheet never leaks state into the next session.
struct CueNotesSheet: View {

    let cueLabel: String
    let initialNotes: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draft: String

    init(
        cueLabel: String,
        initialNotes: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cueLabel = cueLabel
        self.initialNotes = initialNotes
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: initialNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notes — \(cueLabel)")
                .font(.headline)

            TextEditor(text: $draft)
                .font(.body)
                .frame(minWidth: 380, minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                )
                .accessibilityIdentifier("cueNotesSheetEditor")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cueNotesSheetCancel")
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("cueNotesSheetSave")
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .accessibilityIdentifier("cueNotesSheet")
    }

    // MARK: - Test hooks
    //
    // We can't write to `draft` from outside SwiftUI's hosting machinery —
    // @State pre-hosting is a no-op. So tests verify behavior by constructing
    // the sheet with the desired `initialNotes`, then invoking the commit /
    // cancel paths directly.
    var testCurrentDraft: String { draft }
    func testCommit() { onSave(draft) }
    func testCancel() { onCancel() }
}
