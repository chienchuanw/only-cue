import SwiftUI

/// The currently-active media item's filename, shown as a quiet centered line
/// at the top of the `CueListPane` content, above the SMPTE playhead clock, on
/// the plain panel background (#575; #585 keeps it as content rather than a
/// toolbar item so it can be centered over the inspector and sit on the app
/// background instead of toolbar material).
///
/// Matches the LTC strip's clip-name treatment (`DS.Text.small`, sans 11pt —
/// #553) so the two clip-name labels read consistently. A muted placeholder is
/// rendered when no media is loaded so the strip keeps a stable height.
struct ActiveMediaNameHeader: View {

    /// `MediaItem.resolvedName` of the active item, or `nil` when none is loaded.
    let name: String?

    /// Shown when no media is loaded.
    static let placeholder = "No media"

    /// Pure mapping from the optional resolved name to the label string.
    static func displayText(for resolvedName: String?) -> String {
        guard let resolvedName, !resolvedName.isEmpty else { return placeholder }
        return resolvedName
    }

    /// Whether the label is currently the placeholder (drives the quieter color).
    static func isPlaceholder(for resolvedName: String?) -> Bool {
        resolvedName?.isEmpty ?? true
    }

    var body: some View {
        Text(Self.displayText(for: name))
            .font(DS.Text.small)
            .foregroundStyle(Self.isPlaceholder(for: name) ? DS.Color.textTertiary : DS.Color.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, DS.Space.md)
            .padding(.top, DS.Space.sm)
            .accessibilityIdentifier("activeMediaNameHeader")
    }
}
