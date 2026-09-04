import SwiftUI

/// Single source of truth for the user's MTC output configuration
/// (`MTCOutputSettings`), persisted as JSON in `UserDefaults` under
/// `mtcOutput.v1`. Corrupt or absent data → `MTCOutputSettings.default`.
/// Mirrors `LTCRoutingStore`.
///
/// The MIDI preferences pane mutates this through `update(_:)`; `MTCOutputHost`
/// reads `settings` to decide whether to run the generator and where to send.
@MainActor
final class MTCOutputStore: ObservableObject {

    static let storageKey = "mtcOutput.v1"
    static let shared = MTCOutputStore()

    @Published private(set) var settings: MTCOutputSettings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    func update(_ newSettings: MTCOutputSettings) {
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
    /// stores. The same trap `LTCRoutingStore` documents from #697.
    private var suppressPersistenceForUITests = false

    /// Sets MTC output in memory only, and suppresses this store's persistence.
    /// A UI-test hook so the MIDI settings pane can be captured configured
    /// without writing the user's real `mtcOutput.v1`.
    func applyEphemeralForUITests(_ newSettings: MTCOutputSettings) {
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

    static func decode(_ data: Data?) -> MTCOutputSettings {
        guard let data else { return .default }
        return (try? JSONDecoder().decode(MTCOutputSettings.self, from: data)) ?? .default
    }
}
