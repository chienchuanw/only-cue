import SwiftUI
import AppKit

extension DS {

    /// Appearance-aware Quiet Pro color tokens. Each token resolves through a
    /// single `NSColor` dynamic provider — no view branches on `colorScheme`,
    /// and dark mode is changed by editing this file alone. OKLCH (hue ~85°)
    /// is the design-time source of truth, recorded in the trailing comment;
    /// the shipped hex is its sRGB conversion.
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

        /// Builds a `Color` whose value follows the system appearance.
        private static func dynamic(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return nsColor(hex: isDark ? dark : light)
            })
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
