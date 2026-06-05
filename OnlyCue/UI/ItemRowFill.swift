import SwiftUI

/// Resolves a media-sidebar row's selection-pill fill. Figma `318:1238`: the
/// active row shows an inset rounded pill in the selection neutral; every other
/// row is clean. Pure so the precedence is unit-tested without a view.
enum ItemRowFill {

    static func color(isActive: Bool, selection: Color) -> Color {
        isActive ? selection : .clear
    }
}
