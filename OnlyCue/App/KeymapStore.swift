import SwiftUI

/// Single source of truth for the user's keymap, persisted as JSON in
/// `UserDefaults` under `keymap.v1`. Corrupt or absent data → `Keymap.default`.
///
/// `AppCommands` and the document window will read `keymap` to apply shortcuts;
/// the Settings → Keyboard editor will mutate it through `rebind` / `reset*`.
/// Those consumers land in later leaves of epic #40 — this type is the seam.
@MainActor
final class KeymapStore: ObservableObject {

    static let storageKey = "keymap.v1"
    static let shared = KeymapStore()

    @Published private(set) var keymap: Keymap

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keymap = Keymap.decode(defaults.data(forKey: Self.storageKey))
    }

    func rebind(_ action: KeymapAction, to chord: KeyChord) {
        keymap.rebind(action, to: chord)
        persist()
    }

    func resetToDefault(_ action: KeymapAction) {
        keymap.resetToDefault(action)
        persist()
    }

    func resetAll() {
        keymap.resetAll()
        persist()
    }

    /// Re-reads from `UserDefaults` (e.g. after an external import). Mostly a
    /// hook for tests of the persisted round-trip.
    func reload() {
        keymap = Keymap.decode(defaults.data(forKey: Self.storageKey))
    }

    private func persist() {
        guard let data = try? keymap.encoded() else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
