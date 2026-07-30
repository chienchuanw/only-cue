import Foundation

/// Whether the transport bar's timecode readout appears, and what it calls
/// itself. Pure, so the decision is testable without standing up a document
/// window — `TransportControls` only renders it.
enum TimecodeReadout {

    /// The readout used to be gated on `LTCRoutingStore.settings.isEnabled` —
    /// the LTC *output* master switch — so reading the timecode on a file meant
    /// first enabling timecode *generation*, which is an unrelated feature and
    /// off by default (#712). Reading and generating are now independent: the
    /// readout shows whenever there's something to show.
    static func isVisible(hasFileTimecode: Bool, ltcOutputEnabled: Bool) -> Bool {
        hasFileTimecode || ltcOutputEnabled
    }

    /// `FILE` when the value was decoded off the media file's own LTC, `SMPTE`
    /// when OnlyCue computed it from the project's timecode settings. Two
    /// numbers that look identical can mean very different things, and on a show
    /// the difference matters.
    static func prefix(hasFileTimecode: Bool) -> String {
        hasFileTimecode ? "FILE" : "SMPTE"
    }
}
