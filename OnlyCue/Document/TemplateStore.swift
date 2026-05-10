import Foundation

/// Reads and writes `CueListTemplate` files under the user's Documents
/// directory. The directory location is fixed (per epic #39's "Done when":
/// `~/Documents/OnlyCue/Templates`); creating the dir on first use keeps
/// the user from having to mkdir manually.
///
/// Append-merge semantics for load are NOT enforced here — the store does
/// pure encode/decode + filesystem listing. The merge step (assigning fresh
/// UUIDs to loaded types and appending to `ProjectModel.cuePointTypes`) is
/// the caller's job, so tests can pin the merge logic independently of disk
/// I/O.
enum TemplateStore {

    static let fileExtension = "cuelist-template"

    /// `~/Documents/OnlyCue/Templates`. Creating-on-demand at write time.
    static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OnlyCue", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)
    }

    static func save(_ template: CueListTemplate, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(template)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> CueListTemplate {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CueListTemplate.self, from: data)
    }

    /// Returns every `*.cuelist-template` URL under `defaultDirectory`,
    /// sorted by filename. Returns an empty array (not a thrown error) when
    /// the directory doesn't exist yet — the user just hasn't saved any
    /// templates.
    static func list() throws -> [URL] {
        let dir = defaultDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )
        return urls
            .filter { $0.pathExtension == Self.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Append-merge the template's types into the project. Each loaded type
    /// gets a FRESH UUID so loading the same template twice doesn't produce
    /// duplicate IDs and existing cues' typeIDs are unaffected. ADR-015.
    static func appendMerge(template: CueListTemplate, into types: [CuePointType]) -> [CuePointType] {
        let renumbered = template.cuePointTypes.map { type -> CuePointType in
            var fresh = type
            fresh.id = UUID()
            return fresh
        }
        return types + renumbered
    }
}
