import Foundation

/// Pure formatter for the LTC-detected badge label.
///
/// Maps a zero-based audio channel index to a human-readable name:
/// - index 0 → "L" (left)
/// - index 1 → "R" (right)
/// - index >= 2 → "Ch \(index + 1)"
///
/// The mapping is index-based and does not require `channelCount` to be present.
/// `channelCount` is accepted for forward-compatibility but does not alter the
/// L/R/Ch mapping defined above.
enum LTCBadgeLabel {

    /// Returns a display string naming the LTC channel and its muted state.
    ///
    /// Example output: `"R = LTC (muted) · 01:00:00:00"`
    ///
    /// - Parameters:
    ///   - channel: Zero-based index of the audio channel carrying LTC.
    ///   - channelCount: Total channel count of the asset, if known. Accepted
    ///     for forward-compatibility; does not change the L/R/Ch mapping.
    ///   - startTimecode: The detected start timecode display string.
    static func text(channel: Int, channelCount: Int?, startTimecode: String) -> String {
        let channelName: String
        switch channel {
        case 0:  channelName = "L"
        case 1:  channelName = "R"
        default: channelName = "Ch \(channel + 1)"
        }
        return "\(channelName) = LTC (muted) · \(startTimecode)"
    }
}
