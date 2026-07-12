import Foundation

/// Layout contract for the lyric inspector's placed rows. Single source of
/// truth for the timestamp column so the width literal cannot silently drift
/// below what `LyricsTimeFormat.clockString` actually renders (#615) —
/// `LyricsInspectorTimestampColumnTests` measures the rendered string against
/// this value.
enum LyricsInspectorMetrics {
    /// Width of the read-only timestamp column. The clock format renders 10
    /// monospaced glyphs ("00:00:00.0" ≈ 66pt at the DS 11pt mono size); the
    /// old 62pt literal wrapped every timestamp onto a second line. 68pt fits
    /// the widest sub-10h string with a little headroom while keeping the
    /// lyric text's shared left edge close to Figma 318:1490 (text at x=81).
    static let timestampColumnWidth: CGFloat = 68
}
