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
            items: [],
            activeItemID: nil
        )
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
