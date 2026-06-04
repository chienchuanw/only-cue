import AppKit

/// Pins the whole app to a fixed **dark** appearance, regardless of the host's
/// System Settings → Appearance choice (ADR-029, dark-only main window).
///
/// `DS.Color` already resolves every token to its dark value, but that only
/// covers OnlyCue-drawn surfaces. System-drawn chrome — window titlebars,
/// sheets, menus, scrollbars, focus rings, text-field styling — follows
/// `NSApp.appearance`. Pinning it to Dark Aqua keeps that chrome consistent
/// with the dark Figma design system on a Light-mode Mac.
///
/// Unlike `UITestAppearanceHandler` (a `#if DEBUG` test hook), this ships in
/// production. In DEBUG, the UI-test appearance override is applied *after*
/// this, so a `--ui-test-appearance=light` capture can still pin Light.
enum AppAppearance {

    /// The single shipped appearance for the app.
    static let production: NSAppearance.Name = .darkAqua

    /// Pins `NSApp.appearance` to the production (dark) appearance.
    @MainActor
    static func applyDarkOnly() {
        NSApp.appearance = NSAppearance(named: production)
    }
}
