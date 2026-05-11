import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cueList = UTType(exportedAs: "com.onlycue.cuelist")
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
        else { return [ProjectModel.makeDefaultCuePointType()] }
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
        self.model = try ProjectModel.decode(from: data)
    }

    func snapshot(contentType: UTType) throws -> ProjectModel {
        model
    }

    func fileWrapper(snapshot: ProjectModel, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return FileWrapper(regularFileWithContents: data)
    }
}
