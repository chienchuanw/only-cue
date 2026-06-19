import SwiftUI

/// Media file-picker handlers for `DocumentView`: import (new items) and relink
/// (repoint an existing item, #577). Split into an extension so the main
/// `DocumentView` body stays under the SwiftLint `file_length` /
/// `type_body_length` caps.
extension DocumentView {

    func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importURLs(urls)
        case .failure(let error):
            pendingAlert = .unsupported(error.localizedDescription)
        }
    }

    /// Binding that presents the relink picker while a target item is pending.
    var relinkPickerPresented: Binding<Bool> {
        Binding(
            get: { relinkTarget != nil },
            set: { if !$0 { relinkTarget = nil } }
        )
    }

    func handleRelinkResult(_ result: Result<[URL], Error>) {
        guard let itemID = relinkTarget else { return }
        relinkTarget = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            relinkURL(url, itemID: itemID)
        case .failure(let error):
            pendingAlert = .unsupported(error.localizedDescription)
        }
    }

    private func relinkURL(_ url: URL, itemID: MediaItem.ID) {
        Task { @MainActor in
            do {
                try await MediaImporter.relinkMedia(
                    from: url,
                    itemID: itemID,
                    into: document,
                    engine: engine,
                    undoManager: undoManager
                )
            } catch let MediaImportError.unsupportedType(filename) {
                pendingAlert = .unsupported(unsupportedMessage([filename]))
            } catch {
                pendingAlert = .unsupported(error.localizedDescription)
            }
        }
    }

    func importURLs(_ urls: [URL]) {
        Task { @MainActor in
            do {
                try await MediaImporter.importMedia(
                    from: urls,
                    into: document,
                    engine: engine,
                    undoManager: undoManager
                )
            } catch let MediaImportError.batch(unsupported) {
                pendingAlert = .unsupported(unsupportedMessage(unsupported))
            } catch {
                pendingAlert = .unsupported(error.localizedDescription)
            }
        }
    }

    private func unsupportedMessage(_ filenames: [String]) -> String {
        let list = filenames.joined(separator: ", ")
        return filenames.count == 1
            ? "\(list) isn't a supported audio or video file."
            : "These files weren't supported and were skipped: \(list)"
    }
}
