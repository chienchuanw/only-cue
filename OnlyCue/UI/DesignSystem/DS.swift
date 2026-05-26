import SwiftUI

/// The Quiet Pro design-token namespace. Every main-window view consumes
/// `DS.*` instead of raw color, spacing, font, or radius literals. See
/// `docs/superpowers/specs/2026-05-21-quiet-pro-ui-redesign-design.md`.
enum DS {

    /// 4 pt spacing grid. Use with rhythm — tight within a group, generous
    /// between zones — never uniformly.
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Corner radii.
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        // Sectioned-card radius (audit §1.4 / §2.1 / §2.3) — matches the
        // Figma "panel card" container used for grouped settings controls.
        static let xl: CGFloat = 12
    }

    /// Motion. Ease-out only; motion conveys state, never decoration.
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
        static let standard = Animation.easeOut(duration: 0.22)
    }
}
