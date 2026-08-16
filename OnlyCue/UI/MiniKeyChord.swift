import AppKit

/// Converts an `NSEvent` key-down's characters + modifier flags into a `KeyChord`
/// so the pure `MiniPlaybackKeymap` can resolve it (#743). Mirrors
/// `KeyChord.from(keyEquivalent:modifiers:)` but works from AppKit's event data.
enum MiniKeyChord {

    private static let specialByScalar: [Int: String] = [
        NSLeftArrowFunctionKey: "leftArrow",
        NSRightArrowFunctionKey: "rightArrow",
        NSUpArrowFunctionKey: "upArrow",
        NSDownArrowFunctionKey: "downArrow"
    ]

    static func from(charactersIgnoringModifiers chars: String?, flags: NSEvent.ModifierFlags) -> KeyChord? {
        guard let chars, let first = chars.unicodeScalars.first else { return nil }

        var mods: Set<KeyChord.Modifier> = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }

        if let name = specialByScalar[Int(first.value)] { return KeyChord(key: name, modifiers: mods) }
        switch first {
        case " ": return KeyChord(key: "space", modifiers: mods)
        case "\r", "\u{3}": return KeyChord(key: "return", modifiers: mods)
        default: break
        }
        guard chars.count == 1 else { return nil }
        return KeyChord(key: chars.lowercased(), modifiers: mods)
    }
}
