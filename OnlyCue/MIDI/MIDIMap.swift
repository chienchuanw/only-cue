import Foundation

/// The user's MIDI bindings: one `MIDIAction` per physical control
/// (control-as-key, spec decision). Re-learning a control reassigns it; two
/// controls may map to the same action. Absent/corrupt data → empty map.
///
/// On disk it is a flat `{controlToken: actionToken}` JSON object (unknown or
/// unparseable entries are dropped on decode) — mirrors `Keymap`'s lenient
/// `[String: KeyChord]` shape.
struct MIDIMap: Codable, Equatable, Sendable {
    private(set) var bindings: [MIDIControlID: MIDIAction]

    static let `default` = Self(bindings: [:])

    init(bindings: [MIDIControlID: MIDIAction]) { self.bindings = bindings }

    // MARK: Queries

    func action(for control: MIDIControlID) -> MIDIAction? { bindings[control] }

    /// Controls currently bound to `action`, in no particular order.
    func controls(for action: MIDIAction) -> [MIDIControlID] {
        bindings.compactMap { $0.value == action ? $0.key : nil }
    }

    // MARK: Mutation

    mutating func learn(_ control: MIDIControlID, as action: MIDIAction) {
        bindings[control] = action
    }

    mutating func clear(_ control: MIDIControlID) {
        bindings[control] = nil
    }

    // MARK: Persistence

    static func decode(_ data: Data?) -> Self {
        guard let data,
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return .default }
        return Self(bindings: Self.bindings(from: stored))
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(storedForm)
    }

    /// Drops entries whose control or action token is unknown / unparseable.
    private static func bindings(from stored: [String: String]) -> [MIDIControlID: MIDIAction] {
        var bindings: [MIDIControlID: MIDIAction] = [:]
        for (controlToken, actionToken) in stored {
            if let control = MIDIControlID(token: controlToken),
               let action = MIDIAction(token: actionToken) {
                bindings[control] = action
            }
        }
        return bindings
    }

    private var storedForm: [String: String] {
        Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.token, $0.value.token) })
    }

    // MARK: Codable — delegate to the flat-token form above.

    init(from decoder: Decoder) throws {
        let stored = try decoder.singleValueContainer().decode([String: String].self)
        self.init(bindings: Self.bindings(from: stored))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedForm)
    }
}
