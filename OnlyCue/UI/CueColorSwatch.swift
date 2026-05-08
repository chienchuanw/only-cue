import SwiftUI

/// Small filled circle representing a cue/Type color. Falls back to gray when the hex
/// can't be parsed. Used by the cue inspector's Type picker and the cue row's color popover.
struct CueColorSwatch: View {
    let hex: String
    var diameter: CGFloat = 12

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: diameter, height: diameter)
    }
}
