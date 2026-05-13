import Foundation

/// The user's keyboard map: one `KeyChord` per `KeymapAction`.
///
/// A `Keymap` is always **total** — there is a binding for every action. When
/// decoded from JSON, any action missing from the stored data is filled from
/// `defaultBindings` (so a keymap written by an older build still resolves
/// actions added since), and any stored key that isn't a known `KeymapAction`
/// is ignored. Corrupt or absent data yields `Keymap.default`.
struct Keymap: Codable, Equatable, Sendable {

    private(set) var bindings: [KeymapAction: KeyChord]

    static let `default` = Self(bindings: defaultBindings)

    init(bindings: [KeymapAction: KeyChord]) {
        // Backfill any missing action so the map stays total.
        var complete = Self.defaultBindings
        for (action, chord) in bindings { complete[action] = chord }
        self.bindings = complete
    }

    // MARK: - Queries

    func chord(for action: KeymapAction) -> KeyChord {
        bindings[action] ?? Self.defaultBindings[action] ?? KeyChord(key: action.rawValue)
    }

    /// Chords bound to more than one action. Empty when the map is conflict-free.
    func conflicts() -> [KeyChord: [KeymapAction]] {
        var byChord: [KeyChord: [KeymapAction]] = [:]
        for (action, chord) in bindings { byChord[chord, default: []].append(action) }
        return byChord.filter { $0.value.count > 1 }
    }

    /// Actions already bound to `chord`, other than `action` itself — i.e. what
    /// rebinding `action` to `chord` would collide with.
    func actionsConflicting(with chord: KeyChord, excluding action: KeymapAction) -> [KeymapAction] {
        bindings.compactMap { boundAction, boundChord in
            boundAction != action && boundChord == chord ? boundAction : nil
        }
    }

    // MARK: - Mutation

    mutating func rebind(_ action: KeymapAction, to chord: KeyChord) {
        bindings[action] = chord
    }

    mutating func resetToDefault(_ action: KeymapAction) {
        bindings[action] = Self.defaultBindings[action]
    }

    mutating func resetAll() {
        bindings = Self.defaultBindings
    }

    // MARK: - Persistence

    /// Lenient decode for the store: `nil` / corrupt / partial all resolve to a
    /// total keymap (missing actions backfilled, unknown keys dropped).
    static func decode(_ data: Data?) -> Self {
        guard let data else { return .default }
        return (try? JSONDecoder().decode(Self.self, from: data)) ?? .default
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: - Codable — the on-disk shape is a plain `{actionRawValue: KeyChord}`
    // JSON object; unknown keys are dropped, missing actions backfilled.

    init(from decoder: Decoder) throws {
        let stored = try decoder.singleValueContainer().decode([String: KeyChord].self)
        var bindings: [KeymapAction: KeyChord] = [:]
        for (rawAction, chord) in stored {
            if let action = KeymapAction(rawValue: rawAction) { bindings[action] = chord }
        }
        self.init(bindings: bindings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) }))
    }

    // MARK: - Defaults — mirrors the `.keyboardShortcut(...)` calls in `AppCommands`
    // and the document window's number-key cue creation.

    static let defaultBindings: [KeymapAction: KeyChord] = [
        .importMedia: KeyChord(key: "o", modifiers: [.command]),
        .exportCues: KeyChord(key: "e", modifiers: [.command, .shift]),
        .waveformZoomIn: KeyChord(key: "=", modifiers: [.command]),
        .waveformZoomOut: KeyChord(key: "-", modifiers: [.command]),
        .waveformZoomReset: KeyChord(key: "0", modifiers: [.command]),
        .waveformVerticalZoomIn: KeyChord(key: "=", modifiers: [.command, .option]),
        .waveformVerticalZoomOut: KeyChord(key: "-", modifiers: [.command, .option]),
        .waveformVerticalZoomReset: KeyChord(key: "0", modifiers: [.command, .option]),
        .toggleNotesOverlay: KeyChord(key: "n", modifiers: [.command, .shift]),
        .toggleTimelineBreakdown: KeyChord(key: "b", modifiers: [.command, .shift]),
        .toggleTempoGrid: KeyChord(key: "g", modifiers: [.command, .shift]),
        .togglePauseAtEachCue: KeyChord(key: "p", modifiers: [.command, .shift]),
        .splitTempoSectionAtPlayhead: KeyChord(key: "t", modifiers: [.command, .shift]),
        .snapSelectedCueToPlayhead: KeyChord(key: "s"),
        .duplicateCueAtPlayhead: KeyChord(key: "d", modifiers: [.command]),
        .nudgeSelectedCueBack: KeyChord(key: "leftArrow", modifiers: [.option]),
        .nudgeSelectedCueForward: KeyChord(key: "rightArrow", modifiers: [.option]),
        .playPause: KeyChord(key: "space"),
        .jumpBack: KeyChord(key: "leftArrow"),
        .jumpForward: KeyChord(key: "rightArrow"),
        .stepPrevCue: KeyChord(key: "upArrow"),
        .stepNextCue: KeyChord(key: "downArrow"),
        .addCue: KeyChord(key: "m"),
        .addCueOfType0: KeyChord(key: "0"),
        .addCueOfType1: KeyChord(key: "1"),
        .addCueOfType2: KeyChord(key: "2"),
        .addCueOfType3: KeyChord(key: "3"),
        .addCueOfType4: KeyChord(key: "4"),
        .addCueOfType5: KeyChord(key: "5"),
        .addCueOfType6: KeyChord(key: "6"),
        .addCueOfType7: KeyChord(key: "7"),
        .addCueOfType8: KeyChord(key: "8"),
        .addCueOfType9: KeyChord(key: "9")
    ]
}
