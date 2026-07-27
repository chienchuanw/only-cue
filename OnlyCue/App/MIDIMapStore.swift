import SwiftUI

/// Single source of truth for the user's MIDI bindings (`MIDIMap`) and the
/// chosen input device UID, persisted as JSON in `UserDefaults` under
/// `midiMap.v1` / `midiInput.v1`. Corrupt or absent data → empty map / nil
/// device. Mirrors `KeymapStore` / `LTCRoutingStore`.
///
/// No global suppression flag — tests inject their own `UserDefaults`, so the
/// #697 class of "persistence silently disabled process-wide" cannot occur here.
@MainActor
final class MIDIMapStore: ObservableObject {

    static let storageKey = "midiMap.v1"
    static let inputKey = "midiInput.v1"
    static let shared = MIDIMapStore()

    @Published private(set) var map: MIDIMap
    @Published private(set) var selectedInputUID: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        map = MIDIMap.decode(defaults.data(forKey: Self.storageKey))
        selectedInputUID = defaults.string(forKey: Self.inputKey)
    }

    func learn(_ control: MIDIControlID, as action: MIDIAction) {
        map.learn(control, as: action)
        persist()
    }

    func clear(_ control: MIDIControlID) {
        map.clear(control)
        persist()
    }

    func resetAll() {
        map = .default
        persist()
    }

    func selectInput(uid: String?) {
        selectedInputUID = uid
        if let uid {
            defaults.set(uid, forKey: Self.inputKey)
        } else {
            defaults.removeObject(forKey: Self.inputKey)
        }
    }

    /// Re-reads from `UserDefaults` — mostly a hook for round-trip tests.
    func reload() {
        map = MIDIMap.decode(defaults.data(forKey: Self.storageKey))
        selectedInputUID = defaults.string(forKey: Self.inputKey)
    }

    private func persist() {
        guard let data = try? map.encoded() else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
