import Foundation

@MainActor
enum CueCommands {

    static func replaceAll(_ cues: [Cue], in document: CueListDocument) {
        document.model.cues = cues
    }
}
