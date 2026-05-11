import SwiftUI

/// Small `Binding` adapters lifted out of `DocumentView` so the struct stays
/// under SwiftLint's `type_body_length` cap. Same extension-in-its-own-file
/// pattern as `DocumentView+PauseAtEachCue.swift`.
extension DocumentView {

    /// Bridges the export / template actions' optional error-message output
    /// into the document's `pendingAlert`. The getter always returns nil —
    /// these actions never *read* the message back, they only set it.
    var pendingAlertMessageBinding: Binding<String?> {
        Binding(get: { nil }, set: { if let msg = $0 { pendingAlert = .unsupported(msg) } })
    }

    /// `isPresented` for the first-launch sheet — inverted view over the
    /// `didShowFirstLaunch` `@AppStorage` flag.
    var firstLaunchBinding: Binding<Bool> {
        Binding(get: { !didShowFirstLaunch }, set: { if !$0 { didShowFirstLaunch = true } })
    }

    /// Decodes / re-encodes the notes-overlay preferences blob for the
    /// appearance sheet.
    var overlayPrefsBinding: Binding<NotesOverlayPreferences> {
        Binding(
            get: { NotesOverlayPreferences.decode(overlayPrefsData) },
            set: { overlayPrefsData = $0.encoded }
        )
    }
}
