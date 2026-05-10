import SwiftUI

/// Caption-style cheatsheet rendered in the empty-document footer.
/// Lists the shortcuts a new user is least likely to discover from menus
/// alone (`M` to add a cue, `↑↓` to step, `⇧⌘N` for the notes overlay,
/// `⇧⌘P` for pause-at-each-cue). Extracted from `DocumentView` to keep that
/// struct under SwiftLint's `type_body_length` cap.
struct DocumentShortcutHints: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("Drop files on the sidebar or press ⌘O to import.")
            Text("M — add cue at playhead   •   ↑ ↓ — step cues")
            Text("⇧⌘N — notes overlay   •   ⇧⌘P — pause at each cue")
        }
        .font(.system(.caption, design: .monospaced))
        .multilineTextAlignment(.center)
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
        .accessibilityIdentifier("documentShortcutHints")
    }
}
