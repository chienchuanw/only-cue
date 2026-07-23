import SwiftUI

/// Single source of truth for the user's LTC output routing (`LTCRoutingSettings`),
/// persisted as JSON in `UserDefaults` under `ltcRouting.v1`. Corrupt or absent
/// data → `LTCRoutingSettings.default`. Mirrors `KeymapStore`.
///
/// The Audio & Timecode preferences pane will mutate this through `update(_:)`;
/// the LTC playback path (a later leaf) will read `settings` to decide which
/// device / channel carries the generated timecode. This type is the seam.
@MainActor
final class LTCRoutingStore: ObservableObject {

    static let storageKey = "ltcRouting.v1"
    static let shared = LTCRoutingStore()

    @Published private(set) var settings: LTCRoutingSettings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    func update(_ newSettings: LTCRoutingSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        persist()
    }

    func resetToDefault() {
        update(.default)
    }

    /// Re-reads from `UserDefaults` — mostly a hook for tests of the persisted
    /// round-trip.
    func reload() {
        settings = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    #if DEBUG
    /// When true, `persist()` is a no-op for *this* store — it runs in memory.
    /// Scoped per-instance (not process-global) so enabling it on the UI-test
    /// `shared` store never leaks into unit tests that construct their own
    /// stores; a lingering CI marker used to no-op every store's persistence in
    /// the unit-test host (#697).
    private var suppressPersistenceForUITests = false

    /// Sets routing in memory only, and suppresses this store's persistence. A
    /// UI-test hook (see `UITestLTCHandler`) so the Audio settings pane can be
    /// captured configured without writing the persisted default — and without
    /// the settings pane's on-appear `reconcileChannelCount` touching the user's
    /// `ltcRouting.v1`. Only ever called on `shared`, leaving other stores
    /// (unit tests) persisting normally.
    func applyEphemeralForUITests(_ newSettings: LTCRoutingSettings) {
        suppressPersistenceForUITests = true
        settings = newSettings
    }
    #endif

    private func persist() {
        #if DEBUG
        if suppressPersistenceForUITests { return }
        #endif
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func decode(_ data: Data?) -> LTCRoutingSettings {
        guard let data else { return .default }
        return (try? JSONDecoder().decode(LTCRoutingSettings.self, from: data)) ?? .default
    }
}
