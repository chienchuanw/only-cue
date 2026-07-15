import Foundation

/// The file I/O for Export Bundle (#640): given a planned `BundleLayout`, create
/// `media/`, copy each unique source file in, and write the `.cuelist` with
/// `bundlePath` stamped onto every item. Split from `BundleExportAction` so the
/// I/O is integration-testable without NSSavePanel. `destination` must not
/// already exist — the caller clears any prior folder (NSSavePanel overwrite).
enum BundleWriter {

    static func write(
        layout: BundleLayout,
        model: ProjectModel,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        let mediaDir = destination.appendingPathComponent("media", isDirectory: true)
        try fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        for entry in layout.entries {
            // The source may be a security-scoped bookmark URL; reading its bytes
            // (copyItem) needs scoped access started, like every other media-read
            // site (MediaImporter, MediaPreviewStrip, CueTempoDetect). A plain
            // fallback URL returns false and needs no bracket.
            let scoped = entry.source.startAccessingSecurityScopedResource()
            defer { if scoped { entry.source.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: entry.source, to: mediaDir.appendingPathComponent(entry.destName))
        }

        var stamped = model
        stamped.items = model.items.map { item in
            var copy = item
            copy.media.bundlePath = layout.bundlePathByItem[item.id]
            return copy
        }

        let cuelistURL = destination.appendingPathComponent(destination.lastPathComponent + ".cuelist")
        try CueListDocument.encodeModel(stamped).write(to: cuelistURL)
    }
}
