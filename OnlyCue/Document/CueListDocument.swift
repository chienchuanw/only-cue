import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cueList = UTType(exportedAs: "com.onlycue.cuelist")
    /// The portable `.occues` cue-list interchange file (not a document type —
    /// handled via NSOpenPanel/NSSavePanel, never DocumentGroup).
    static let cueListExport = UTType(exportedAs: "com.onlycue.cues")
}

final class CueListDocument: ReferenceFileDocument {
    typealias Snapshot = ProjectModel

    static var readableContentTypes: [UTType] { [.cueList] }
    static var writableContentTypes: [UTType] { [.cueList] }

    @Published var model: ProjectModel

    init() {
        self.model = ProjectModel(
            schemaVersion: ProjectModel.currentSchemaVersion,
            id: UUID(),
            name: "Untitled",
            cuePointTypes: Self.initialCuePointTypes(),
            items: [],
            activeItemID: nil
        )
    }

    /// The CuePointType set a brand-new document starts with: the types from a
    /// pending `New from Template…` command if one is mid-flight (each given a
    /// fresh UUID, per ADR-015 — so two documents made from the same template
    /// don't share type IDs), otherwise the single built-in default. Reading
    /// the pending slot also clears it, so a later plain ⌘N is unaffected.
    private static func initialCuePointTypes() -> [CuePointType] {
        guard let template = TemplateStore.consumePendingNewDocumentTemplate(),
              !template.cuePointTypes.isEmpty
        else { return ProjectModel.makeCanonicalCuePointTypes() }
        return template.cuePointTypes.map { type in
            var fresh = type
            fresh.id = UUID()
            return fresh
        }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        do {
            self.model = try Self.decodeModel(from: data)
        } catch is CuelistCrypto.CryptoError {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func snapshot(contentType: UTType) throws -> ProjectModel {
        model
    }

    func fileWrapper(snapshot: ProjectModel, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encodeModel(snapshot))
    }

    /// Decrypt (or pass through a legacy plaintext file) then run schema migration.
    static func decodeModel(from fileData: Data) throws -> ProjectModel {
        try ProjectModel.decode(from: CuelistCrypto.open(fileData))
    }

    /// Encode to pretty JSON, then seal in the encrypted envelope.
    static func encodeModel(_ model: ProjectModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try CuelistCrypto.seal(try encoder.encode(model))
    }
}
