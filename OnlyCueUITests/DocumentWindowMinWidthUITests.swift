import XCTest

/// Regression guard for issue #617. A populated document window could not
/// shrink below ~1416pt: the `.inspector` modifier inflated the window's
/// minimum width to sidebar + declared detail minWidth + a ~248pt constant +
/// the inspector's *ideal* width — far past the 1280pt design width
/// (`defaultSize` in `OnlyCueApp`). AppKit then grew the window beyond its
/// requested default size at launch, so the observable symptom is a seeded
/// window opening wider than 1280pt (and clipping on 1280-class displays).
final class DocumentWindowMinWidthUITests: OnlyCueUITestCase {

    /// Figma design width: sidebar 240 + preview 680 + inspector 360.
    private static let designWidth: CGFloat = 1280

    func test_populatedDocumentWindow_opensAtDesignWidth() throws {
        let app = launchApp(seed: .setListActI, extraArguments: ["--ui-test-appearance=dark"])
        // The set-list-act-i seed names its document "Set List — Act I.cuelist"
        // (not the legacy `seed-<uuid>` prefix `waitForSeedWindow` matches).
        let window = try waitForDocumentWindow(in: app)

        let width = window.frame.width
        XCTAssertLessThanOrEqual(
            width,
            Self.designWidth,
            "populated document window opened at \(width)pt — its minimum width exceeds the "
                + "1280pt design width, so it cannot fit 1280-class displays (#617)"
        )
    }

    /// Waits for any document window, regardless of the seed's display name.
    /// Matched by containment, not suffix: the AX window title carries the
    /// navigation subtitle too ("Set List — Act I.cuelist – Cue Mode").
    private func waitForDocumentWindow(
        in app: XCUIApplication,
        timeout: TimeInterval = 15
    ) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let windows = app.windows.allElementsBoundByIndex
            if let match = windows.first(where: { $0.title.contains(".cuelist") }) {
                return match
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw XCTestError(.failureWhileWaiting)
    }
}
