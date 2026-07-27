import SwiftUI

/// One in-flight "move a control to bind it" interaction. The Settings pane
/// calls `begin(_:)` for the row the user armed; the document-window host
/// forwards every incoming message here while `isActive`, so the *first* one
/// wins and the session ends itself.
///
/// Shared instance: Learn is armed in Settings but the MIDI stream arrives in
/// the document window's host, so both sides need the same object.
@MainActor
final class MIDILearnSession: ObservableObject {

    static let shared = MIDILearnSession()

    @Published private(set) var target: MIDIAction?

    var isActive: Bool { target != nil }
    var onLearned: ((MIDIControlID, MIDIAction) -> Void)?

    func begin(_ action: MIDIAction) { target = action }

    func cancel() { target = nil }

    /// Binds the first message that carries a usable control identity, then
    /// disarms. Ignored when not armed.
    func capture(_ message: MIDIMessage) {
        guard let action = target, let control = MIDIControlID(message: message) else { return }
        onLearned?(control, action)
        target = nil
    }
}
