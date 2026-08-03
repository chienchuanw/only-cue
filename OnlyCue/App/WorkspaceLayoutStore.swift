import Foundation

/// Everything persisted under `"workspaceLayout.v1"`.
struct WorkspaceState: Codable, Equatable {
    var presets: [WorkspaceLayout]
    var selectedName: String?
    /// The arrangement the frontmost window last had, so a brand-new window
    /// inherits it rather than the factory default (spec scope item 7).
    var mostRecentLayout: WorkspaceLayout

    static let `default` = Self(
        presets: [.default],
        selectedName: nil,
        mostRecentLayout: .default
    )
}

/// App-level workspace preset storage. Layout is the person's habit, not the
/// work's content, so it lives in `UserDefaults` and never in `ProjectModel` —
/// storing it in the document would dirty the file, enter the undo stack and
/// require a schema bump (spec decision 3).
///
/// Mirrors `LTCRoutingStore` / `KeymapStore` / `MIDIMapStore`: `shared`
/// singleton, injectable `UserDefaults` for tests, versioned JSON under one
/// key, `.default` on any decode failure.
@MainActor
final class WorkspaceLayoutStore: ObservableObject {

    static let storageKey = "workspaceLayout.v1"
    static let shared = WorkspaceLayoutStore()

    @Published private(set) var state: WorkspaceState

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    /// The preset currently selected, or nil when the live layout has diverged
    /// from every preset (or none was ever chosen).
    var selectedPreset: WorkspaceLayout? {
        guard let name = state.selectedName else { return nil }
        return state.presets.first { $0.name == name }
    }

    // MARK: - Mutations

    /// Adds `layout` (replacing any preset of the same name) and selects it.
    func save(_ layout: WorkspaceLayout) {
        var next = state
        if let index = next.presets.firstIndex(where: { $0.name == layout.name }) {
            next.presets[index] = layout
        } else {
            next.presets.append(layout)
        }
        next.selectedName = layout.name
        next.mostRecentLayout = layout
        apply(next)
    }

    /// Replaces an existing preset's contents in place, keeping its position.
    /// Refused for the built-in `Default`.
    func overwrite(name: String, with layout: WorkspaceLayout) {
        guard name != WorkspaceLayout.defaultName else { return }
        guard let index = state.presets.firstIndex(where: { $0.name == name }) else { return }
        var next = state
        var replacement = layout
        replacement.name = name
        next.presets[index] = replacement
        next.selectedName = name
        next.mostRecentLayout = replacement
        apply(next)
    }

    /// Refused for the built-in `Default` and for a name already in use.
    func rename(_ name: String, to newName: String) {
        guard name != WorkspaceLayout.defaultName else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != WorkspaceLayout.defaultName else { return }
        guard !state.presets.contains(where: { $0.name == trimmed }) else { return }
        guard let index = state.presets.firstIndex(where: { $0.name == name }) else { return }

        var next = state
        next.presets[index].name = trimmed
        if next.selectedName == name { next.selectedName = trimmed }
        apply(next)
    }

    /// Refused for the built-in `Default`.
    func delete(_ name: String) {
        guard name != WorkspaceLayout.defaultName else { return }
        var next = state
        next.presets.removeAll { $0.name == name }
        if next.selectedName == name { next.selectedName = nil }
        apply(next)
    }

    func select(_ name: String?) {
        var next = state
        next.selectedName = name
        apply(next)
    }

    /// Records the frontmost window's current arrangement. Deliberately does
    /// NOT touch `presets` — a preset is a snapshot, so dragging a divider
    /// after selecting one must leave that preset byte-identical.
    func recordLiveLayout(_ layout: WorkspaceLayout) {
        var next = state
        next.mostRecentLayout = layout
        apply(next)
    }

    func resetToDefault() {
        apply(.default)
    }

    func reload() {
        state = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    // MARK: - Persistence

    private func apply(_ newState: WorkspaceState) {
        guard newState != state else { return }
        state = newState
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func decode(_ data: Data?) -> WorkspaceState {
        guard let data else { return .default }
        guard var decoded = try? JSONDecoder().decode(WorkspaceState.self, from: data) else {
            return .default
        }
        // The built-in Default is guaranteed present and first, even if an
        // older build or hand-edited defaults dropped it.
        decoded.presets.removeAll { $0.name == WorkspaceLayout.defaultName }
        decoded.presets.insert(.default, at: 0)
        return decoded
    }
}
