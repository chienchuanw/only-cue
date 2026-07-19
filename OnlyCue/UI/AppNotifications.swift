import Foundation

/// App-wide notification names: menu commands and other cross-window requests
/// post these; presenter modifiers on `DocumentView` receive them. Moved out
/// of `DocumentView.swift` to keep it under SwiftLint's `file_length` cap.
extension Notification.Name {
    static let importMediaRequested = Notification.Name("OnlyCue.importMediaRequested")
    static let exportCuesToCSVRequested = Notification.Name("OnlyCue.exportCuesToCSVRequested")
    static let exportCueListRequested = Notification.Name("OnlyCue.exportCueListRequested")
    static let importCueListRequested = Notification.Name("OnlyCue.importCueListRequested")
    static let exportBundleRequested = Notification.Name("OnlyCue.exportBundleRequested")
    static let saveTemplateRequested = Notification.Name("OnlyCue.saveTemplateRequested")
    static let loadTemplateRequested = Notification.Name("OnlyCue.loadTemplateRequested")
    static let oscMonitorRequested = Notification.Name("OnlyCue.oscMonitorRequested")
    static let timecodeSettingsRequested = Notification.Name("OnlyCue.timecodeSettingsRequested")
    static let snapSelectedCuesToBeat = Notification.Name("OnlyCue.snapSelectedCuesToBeat")
    static let snapSelectedCuesToBar = Notification.Name("OnlyCue.snapSelectedCuesToBar")
    static let manageTypesRequested = Notification.Name("OnlyCue.manageTypesRequested")
    static let editorModeChangeRequested = Notification.Name("OnlyCue.editorModeChangeRequested")
    static let playbackRateUp = Notification.Name("OnlyCue.playbackRateUp")
    static let playbackRateDown = Notification.Name("OnlyCue.playbackRateDown")
    static let playbackRateReset = Notification.Name("OnlyCue.playbackRateReset")
    static let playbackRateInterlockBlocked = Notification.Name("OnlyCue.playbackRateInterlockBlocked")
    static let playbackRateInterlockReset = Notification.Name("OnlyCue.playbackRateInterlockReset")
    static let sendToMA2Requested = Notification.Name("OnlyCue.sendToMA2Requested")
}
