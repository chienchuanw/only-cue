import Foundation

/// The decrypted payload of a `.occues` file — one media item's cue list plus
/// the `CuePointType` definitions those cues reference. Schema-independent of
/// `ProjectModel`; versioned by its own `formatVersion`.
struct CueListExport: Codable, Equatable {
    var formatVersion: Int
    var exportedAt: Date
    var sourceMedia: ExportedSourceMedia
    var cuePointTypes: [CuePointType]
    var cues: [Cue]
}

/// Identity of the media a `.occues` file was exported from. Drives the
/// import-time mismatch warning.
struct ExportedSourceMedia: Codable, Equatable {
    var displayName: String
    var duration: TimeInterval
}

/// Encodes/decodes `.occues` files and reconciles an imported cue list into a
/// destination project. Pure logic — no AppKit, no document mutation. The
/// undoable model write lives in `CueCommands.importCueList`.
enum CueListTransfer {

    static let currentFormatVersion = 1

    enum TransferError: Error, Equatable {
        case unsupportedFormatVersion(Int)
        case malformedPayload
    }

    /// Probe used to read `formatVersion` before decoding the whole payload, so
    /// an unknown version surfaces as `.unsupportedFormatVersion` rather than a
    /// generic decode failure.
    private struct FormatProbe: Decodable { let formatVersion: Int }

    // MARK: Codec

    static func encode(_ export: CueListExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(export)
        return try CuelistCrypto.seal(json, magic: CuelistCrypto.cueListExportMagic)
    }

    static func decode(_ data: Data) throws -> CueListExport {
        let json: Data
        do {
            json = try CuelistCrypto.open(
                data,
                magic: CuelistCrypto.cueListExportMagic,
                allowLegacyPlaintext: false
            )
        } catch {
            throw TransferError.malformedPayload
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let probe = try? decoder.decode(FormatProbe.self, from: json) else {
            throw TransferError.malformedPayload
        }
        guard probe.formatVersion == currentFormatVersion else {
            throw TransferError.unsupportedFormatVersion(probe.formatVersion)
        }
        guard let export = try? decoder.decode(CueListExport.self, from: json) else {
            throw TransferError.malformedPayload
        }
        return export
    }

    // MARK: Export

    /// Build a `.occues` payload from one media item. `cuePointTypes` carries
    /// only the types `item.cues` reference, preserving `projectTypes` order.
    static func makeExport(
        of item: MediaItem,
        projectTypes: [CuePointType],
        now: Date = Date()
    ) -> CueListExport {
        let referencedIDs = Set(item.cues.map(\.typeID))
        return CueListExport(
            formatVersion: currentFormatVersion,
            exportedAt: now,
            sourceMedia: ExportedSourceMedia(
                displayName: item.media.displayName,
                duration: item.media.duration
            ),
            cuePointTypes: projectTypes.filter { referencedIDs.contains($0.id) },
            cues: item.cues
        )
    }

    /// True when `item` is plausibly the same media the export came from:
    /// identical display name and a duration within 0.5 s. Drives the
    /// import-time mismatch confirmation.
    static func mediaMatches(_ export: CueListExport, _ item: MediaItem) -> Bool {
        export.sourceMedia.displayName == item.media.displayName
            && abs(export.sourceMedia.duration - item.media.duration) <= 0.5
    }

    // MARK: Import reconciliation

    /// The result of folding a payload's types into a destination catalog.
    struct TypeReconciliation {
        /// New `CuePointType`s to append to the destination's catalog.
        var typesToAdd: [CuePointType]
        /// Maps each payload type's original id to its new id.
        var idMap: [UUID: UUID]
    }

    /// Reconcile imported types against `existing` — the always-additive rule:
    /// every payload type becomes a brand-new destination type (fresh id,
    /// `hotkey` cleared so it can't hijack a destination digit binding). A name
    /// that collides with `existing` (or with a type added earlier in this same
    /// batch) gets a ` (imported)` / ` (imported 2)` … suffix. The destination's
    /// own catalog is never modified by this function.
    static func reconcileTypes(
        _ payloadTypes: [CuePointType],
        existing: [CuePointType]
    ) -> TypeReconciliation {
        var idMap: [UUID: UUID] = [:]
        var typesToAdd: [CuePointType] = []
        var takenNames = Set(existing.map { normalizedName($0.name) })

        for source in payloadTypes {
            let newID = UUID()
            idMap[source.id] = newID
            var copy = source
            copy.id = newID
            copy.hotkey = nil
            copy.name = uniqueName(source.name, taken: takenNames)
            takenNames.insert(normalizedName(copy.name))
            typesToAdd.append(copy)
        }
        return TypeReconciliation(typesToAdd: typesToAdd, idMap: idMap)
    }

    /// Reconcile imported cues for the destination: a fresh `id` per cue
    /// (uniqueness, including against re-imports) and `typeID` remapped through
    /// `idMap`. `cueNumber`, `time`, `name`, `notes`, `fadeTime`, `bpm` and
    /// `beatsPerBar` are preserved verbatim — a console-facing `cueNumber` is
    /// never silently rewritten. A `typeID` absent from `idMap` is left as-is.
    static func reconcileCues(_ payloadCues: [Cue], idMap: [UUID: UUID]) -> [Cue] {
        payloadCues.map { cue in
            var copy = cue
            copy.id = UUID()
            if let mapped = idMap[cue.typeID] {
                copy.typeID = mapped
            }
            return copy
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func uniqueName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(normalizedName(base)) else { return base }
        var candidate = "\(base) (imported)"
        var counter = 2
        while taken.contains(normalizedName(candidate)) {
            candidate = "\(base) (imported \(counter))"
            counter += 1
        }
        return candidate
    }
}
