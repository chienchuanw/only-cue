import Foundation

/// A typed app action decoded from an incoming OSC message. The mapping is a
/// pure function (`from(_:)`) so it's fully testable without a live socket;
/// the dispatch side (turning a command into `PlayerEngine` / `CueCommands`
/// calls) lives in the document layer.
enum OSCCommand: Equatable {
    case play
    case pause
    case stop
    /// Jump relative to the current playhead. Positive = forward, negative =
    /// back. Seconds.
    case skip(seconds: Double)
    /// Jump to an absolute time. Seconds, clamped to >= 0 by the dispatcher.
    case locate(seconds: Double)
    case cueAdd
    case cueNext
    case cuePrev

    /// The OSC address patterns OnlyCue listens for, in display order. Used by
    /// the Settings → OSC pane (copy buttons) and the reference docs. The
    /// `<n>` placeholder denotes an optional numeric argument.
    static let supportedAddressPatterns: [String] = [
        "/onlycue/play",
        "/onlycue/pause",
        "/onlycue/stop",
        "/onlycue/skip <seconds>",
        "/onlycue/locate <seconds>",
        "/onlycue/cue/add",
        "/onlycue/cue/next",
        "/onlycue/cue/prev"
    ]

    /// Pure mapping from a parsed message to a command. Unknown addresses (or
    /// addresses missing a required numeric argument) return nil — the server
    /// logs them to the recent-messages buffer but takes no action.
    static func from(_ message: OSCMessage) -> Self? {
        switch message.addressPattern {
        case "/onlycue/play": .play
        case "/onlycue/pause": .pause
        case "/onlycue/stop": .stop
        case "/onlycue/skip":
            message.arguments.first?.numericValue.map { .skip(seconds: $0) }
        case "/onlycue/locate":
            message.arguments.first?.numericValue.map { .locate(seconds: $0) }
        case "/onlycue/cue/add": .cueAdd
        case "/onlycue/cue/next": .cueNext
        case "/onlycue/cue/prev": .cuePrev
        default: nil
        }
    }
}
