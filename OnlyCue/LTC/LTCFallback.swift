import Foundation

/// Resolves the LTC a consumer should use for a song (#754): the live detection
/// when it succeeds, otherwise the song's remembered value. Pure, so the rule is
/// unit-tested; the async detection + persistence sit in `MediaImporter`.
enum LTCFallback {
    static func resolve(
        detected: StripedTimecodeTrack?,
        remembered: StripedTimecodeTrack?
    ) -> StripedTimecodeTrack? {
        detected ?? remembered
    }
}
