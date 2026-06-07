import SwiftUI
import AppKit

extension DS {

    /// Quiet Pro color tokens. The main window is **dark-only** (ADR-029): every
    /// token resolves to its `dark:` value in *every* system appearance, so the
    /// app matches the dark Figma design system even on a Light-mode Mac. The
    /// `light:` column is retained only as a design-time record of the retired
    /// light palette — it is never shipped. OKLCH (hue ~85°) is the design-time
    /// source of truth, recorded in the trailing comment; the shipped hex is its
    /// sRGB conversion. `AppAppearance.applyDarkOnly()` pins system-drawn chrome
    /// (titlebars, sheets, scrollbars) to dark to match.
    enum Color {
        // Chrome neutrals (warm tint, OKLCH hue ~85°, chroma ~0.005).
        static let surface       = dynamic(light: 0xFBFAF8, dark: 0x232220) // L .99 / .20
        static let panel         = dynamic(light: 0xF4F2ED, dark: 0x2B2926) // L .97 / .23
        static let surfaceSunken = dynamic(light: 0xF1EFEA, dark: 0x1C1B19) // L .96 / .17
        static let border        = dynamic(light: 0xDDDBD4, dark: 0x423F3A) // L .90 / .32
        static let borderStrong  = dynamic(light: 0xC4C1B8, dark: 0x5A564F) // L .82 / .42
        static let textTertiary  = dynamic(light: 0x9A978D, dark: 0x8A877E) // L .66 / .58
        static let textSecondary = dynamic(light: 0x76736A, dark: 0xB3AFA5) // L .52 / .72
        static let textPrimary   = dynamic(light: 0x2B2925, dark: 0xEBE9E3) // L .26 / .93
        // Primary-action fill + the text/icon on it.
        static let ink           = dynamic(light: 0x2B2925, dark: 0xEBE9E3)
        static let inkOn         = dynamic(light: 0xFBFAF8, dark: 0x232220)
        // Achromatic selection fill (cue-type color stays the only chroma).
        static let selection     = dynamic(light: 0xE8E5DE, dark: 0x3A3733)
        // Brand primary — the single chromatic accent ("cue/indigo" in the
        // Figma design system). Resolves to the same hex in both light and
        // dark appearance because the design intent is "always the same
        // saturated indigo on whatever neutral chrome we ship with." Use
        // this for primary actions (Done/Save/Export/Confirm), Toggle
        // on-state, slider tint, segmented-control selected segment, and
        // any small chromatic decorations (cue-mode indicator dot, lyric
        // ribbon tints). Apply with `.tint(DS.Color.cueIndigo)` for
        // primitives that honor `tint`; build dedicated styles
        // (IndigoToggleStyle, IndigoPrimaryButtonStyle) for primitives
        // that don't.
        static let cueIndigo = dynamic(light: 0x5B5BD6, dark: 0x5B5BD6)
        // On-indigo content (text/icons sitting on top of a cueIndigo
        // fill). Always white for AA contrast in both appearances.
        static let onCueIndigo = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)

        /// Lyric accent — systemPurple (`#AF52DE`), the Figma design system's
        /// colour for every lyric element: the editing-lane band, the placed
        /// chips, and the ghost (cursor) chip. Distinct from `cueIndigo` so
        /// lyrics read as their own layer over the cue timeline.
        static let lyric = dynamic(light: 0xAF52DE, dark: 0xAF52DE)

        /// Builds a dark-only token (ADR-029): always resolves to `dark`,
        /// independent of the system appearance. `light` is ignored — kept in
        /// the call site purely as a record of the retired light palette.
        private static func dynamic(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            _ = light
            return SwiftUI.Color(nsColor: nsColor(hex: dark))
        }

        private static func nsColor(hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}
