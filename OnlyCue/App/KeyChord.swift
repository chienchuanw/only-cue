import SwiftUI

/// A key + modifier combination, in a form that round-trips through JSON.
///
/// `KeyboardShortcut` / `KeyEquivalent` / `EventModifiers` are not `Codable`, so
/// the keymap stores this instead and converts on demand via `keyboardShortcut`.
///
/// `key` is a single character for printable keys (`"o"`, `"="`, `"1"`), or one
/// of the reserved names in `specialKeyNames` for non-printable keys
/// (`"leftArrow"`, `"space"`, …). Comparison is case-sensitive on the raw
/// character; the modifier list is treated as a set (order-insensitive in
/// `==` / `hash`).
struct KeyChord: Codable, Equatable, Hashable, Sendable {

    enum Modifier: String, Codable, CaseIterable, Sendable {
        case command, shift, option, control
    }

    let key: String
    let modifiers: Set<Modifier>

    init(key: String, modifiers: Set<Modifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    // MARK: - SwiftUI conversion

    /// The `KeyboardShortcut` for this chord, or `nil` if `key` is neither a
    /// known special-key name nor a single character.
    var keyboardShortcut: KeyboardShortcut? {
        keyEquivalent.map { KeyboardShortcut($0, modifiers: eventModifiers) }
    }

    var keyEquivalent: KeyEquivalent? {
        if let special = Self.specialKeys[key] { return special }
        guard key.count == 1, let character = key.first else { return nil }
        return KeyEquivalent(character)
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }

    // MARK: - Building from a key event

    /// Build a chord from a SwiftUI key event (`KeyPress.key` + `.modifiers`),
    /// or `nil` if the key isn't something we can bind (an unrecognised
    /// function key with no printable character). Modifiers other than the four
    /// we model (caps-lock, numeric-pad…) are ignored. Letter keys are
    /// lower-cased — case is carried by the `.shift` modifier, not the key.
    static func from(keyEquivalent: KeyEquivalent, modifiers: EventModifiers) -> Self? {
        var mods: Set<Modifier> = []
        if modifiers.contains(.command) { mods.insert(.command) }
        if modifiers.contains(.shift) { mods.insert(.shift) }
        if modifiers.contains(.option) { mods.insert(.option) }
        if modifiers.contains(.control) { mods.insert(.control) }

        if let name = specialKeyName(for: keyEquivalent) {
            return Self(key: name, modifiers: mods)
        }
        let character = keyEquivalent.character
        guard character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol else {
            return nil
        }
        return Self(key: String(character).lowercased(), modifiers: mods)
    }

    /// The reserved name for `keyEquivalent` if it's one of the special keys we
    /// model (`leftArrow`, `space`, …); `nil` for ordinary printable keys.
    static func specialKeyName(for keyEquivalent: KeyEquivalent) -> String? {
        specialKeys.first { $0.value.character == keyEquivalent.character }?.key
    }

    // MARK: - Display

    /// e.g. `⇧⌘E`, `⌥←`, `S`. Modifiers in the macOS-canonical order ⌃⌥⇧⌘.
    var displayString: String {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "⌃" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        return prefix + (Self.keySymbols[key] ?? key.uppercased())
    }

    // MARK: - Special-key name table

    /// JSON names for the non-printable keys the app actually uses (plus a few
    /// obvious neighbours, so the editor can offer them later).
    static let specialKeyNames: [String] = Array(specialKeys.keys).sorted()

    private static let specialKeys: [String: KeyEquivalent] = [
        "leftArrow": .leftArrow,
        "rightArrow": .rightArrow,
        "upArrow": .upArrow,
        "downArrow": .downArrow,
        "space": .space,
        "return": .return,
        "tab": .tab,
        "escape": .escape,
        "delete": .delete,
        "pageUp": .pageUp,
        "pageDown": .pageDown,
        "home": .home,
        "end": .end
    ]

    private static let keySymbols: [String: String] = [
        "leftArrow": "←",
        "rightArrow": "→",
        "upArrow": "↑",
        "downArrow": "↓",
        "space": "␣",
        "return": "↩",
        "tab": "⇥",
        "escape": "⎋",
        "delete": "⌫",
        "pageUp": "⇞",
        "pageDown": "⇟",
        "home": "↖",
        "end": "↘"
    ]
}
