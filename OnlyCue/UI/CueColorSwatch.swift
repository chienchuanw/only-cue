import SwiftUI

/// Small filled circle representing a cue/Type color. Falls back to `fallback`
/// (`.accentColor` by default) when `hex` is nil or can't be parsed. Used by the
/// cue inspector's Type picker and the cue row's swatch.
struct CueColorSwatch: View {
    let hex: String?
    var diameter: CGFloat = 12
    var fallback: Color = .accentColor

    var body: some View {
        Circle()
            .fill(Color(hex: hex ?? "") ?? fallback)
            .frame(width: diameter, height: diameter)
    }
}
