import AppKit
import SwiftUI

/// Media file-picker handlers for `DocumentView`: import (new items, SwiftUI
/// `.fileImporter`) and relink (repoint an existing item via an AppKit
/// `NSOpenPanel`, #577/#583). Split into an extension so the main `DocumentView`
/// body stays under the SwiftLint `file_length` / `type_body_length` caps.
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

    /// Open a single-file panel to relink `itemID`, then repoint it. Uses
    /// `NSOpenPanel` rather than a second SwiftUI `.fileImporter` because the
    /// importer's dismissal binding raced the completion handler — the target
    /// id was cleared before the result arrived, so relink silently did nothing
    /// (#583). `relinkTarget` is cleared unconditionally so a later relink of
    /// the same item re-triggers the `onChange` that calls this.
    func presentRelinkPanel(itemID: MediaItem.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaImporter.allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let response = panel.runModal()
        relinkTarget = nil
        guard response == .OK, let url = panel.url else { return }
        relinkURL(url, itemID: itemID)
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
