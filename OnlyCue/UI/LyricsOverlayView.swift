import SwiftUI

/// The pure projection the lyrics HUD renders: the current line's text and the
/// next line's text (if any). `nil` when the playhead is before the first line
/// or there are no lyrics — the HUD then renders nothing.
struct LyricsHUDContent: Equatable {
    let currentText: String
    let nextText: String?

    init?(lyrics: Lyrics, mediaSeconds: TimeInterval) {
        guard let current = lyrics.activeLine(atMediaSeconds: mediaSeconds) else { return nil }
        currentText = current.text
        nextText = lyrics.nextLine(afterMediaSeconds: mediaSeconds)?.text
    }
}

/// Toggleable HUD on the Preview pane: the current lyric line (bright) above the
/// next line (dimmed). A show-caller aid, independent of the Notes Overlay.
/// Renders nothing before the first line / when there are no lyrics.
struct LyricsOverlayView: View {

    let lyrics: Lyrics
    let mediaSeconds: TimeInterval

    var body: some View {
        if let content = LyricsHUDContent(lyrics: lyrics, mediaSeconds: mediaSeconds) {
            VStack(spacing: 6) {
                Text(content.currentText)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.primary)
                if let next = content.nextText {
                    Text(next)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 600)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            .accessibilityIdentifier("lyricsOverlay")
        }
    }
}
