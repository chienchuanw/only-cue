import Foundation

/// File I/O for the PotPlayer bookmark export: given a `BundleLayout` (reused
/// from Export Bundle for source dedupe + collision-safe names), copy each video
/// flat into `destination` and write a paired `<stem>.pbf` beside it.
///
/// Unlike `BundleWriter`, the layout is written flat (no `media/` subfolder) and
/// no `.cuelist` is produced — PotPlayer auto-loads a `.pbf` only when it sits
/// beside the video sharing its base name. Cues are filtered to Types whose
/// `isExportEnabled` is true; a video with no surviving cue still gets an empty
/// `.pbf`. `destination` must not already exist (the action clears any prior).
enum PotPlayerBundleWriter {

    static func write(
        layout: BundleLayout,
        model: ProjectModel,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        // Exclude only cues whose Type is *explicitly* export-disabled. A cue
        // whose Type is missing (dangling reference) is kept — matching
        // PBFExporter's unknown-Type title handling and `isExportEnabled`'s
        // default of true. `CueExportFilter` isn't reused here: its empty
        // `onlyTypeIDs` means "pass all", which would wrongly export everything
        // when every Type is disabled.
        let disabledTypeIDs = Set(
            model.cuePointTypes.filter { !$0.isExportEnabled }.map { $0.id }
        )
        let typeNamesByID = Dictionary(
            uniqueKeysWithValues: model.cuePointTypes.map { ($0.id, $0.name) }
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: model.items.map { ($0.id, $0) })

        for entry in layout.entries {
            // The source may be a security-scoped bookmark URL; reading its bytes
            // (copyItem) needs scoped access started, like BundleWriter /
            // MediaImporter. A plain fallback URL returns false and needs no bracket.
            let scoped = entry.source.startAccessingSecurityScopedResource()
            defer { if scoped { entry.source.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(
                at: entry.source,
                to: destination.appendingPathComponent(entry.destName)
            )

            // A file shared by several items (BundleLayout dedupe) gets all their
            // enabled cues merged into its one `.pbf`.
            let cues = entry.itemIDs
                .compactMap { itemsByID[$0]?.cues }
                .flatMap { $0 }
                .filter { !disabledTypeIDs.contains($0.typeID) }
            let body = PBFExporter.pbf(cues: cues, typeNamesByID: typeNamesByID)
            let pbfName = (entry.destName as NSString).deletingPathExtension + ".pbf"
            try body.write(
                to: destination.appendingPathComponent(pbfName),
                atomically: true,
                encoding: .utf8
            )
        }
    }
}
