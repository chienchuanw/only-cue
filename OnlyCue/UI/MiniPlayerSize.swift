import CoreGraphics

/// Pure width policy for the resizable Mini Player panel (#761). Single source of
/// truth for the min / max / default width and the clamp applied both when the
/// panel is configured and when a persisted (frame-autosave) width is restored.
/// Height is fixed by the panel, so only width is governed here.
enum MiniPlayerSize {
    /// Minimum width: keeps the current cue name visible and the Show-mode GO
    /// button un-squeezed (Figma "Mini Player — Resize Range", min 660).
    static let min: CGFloat = 660
    /// Maximum width: enough for a long CJK title without unbounded growth.
    static let max: CGFloat = 1000
    /// Opening / fallback width.
    static let `default`: CGFloat = 660

    /// Clamp a width into `[min, max]`; non-finite input falls back to `default`.
    static func clamp(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return `default` }
        return Swift.min(Swift.max(width, min), max)
    }
}
