#if DEBUG
import AppKit

/// `#if DEBUG`-only launch handler that pins the document window to a
/// deterministic frame, anchored at the screen's top-left, so screenshot UI
/// tests capture the full window regardless of the capture display's size or
/// orientation. Trigger: pass `--ui-test-window=1280x820` as a launch argument.
///
/// Why this exists (#614): the capture machine runs a portrait display
/// (1296x2304). Before #617 the populated window's ~1416pt minimum pushed it
/// past the right screen edge, so `XCUIElement.screenshot()` silently captured
/// only the on-screen portion — the cue-list inspector's NAME/FADE columns were
/// clipped in every committed baseline. Pinning an on-screen 1280x820 frame
/// makes captures display-independent and reproduces Figma's 1280x812
/// proportions. The screenshot test asserts the achieved frame is exactly the
/// requested size, so a silent clamp fails the capture instead of producing
/// another clipped baseline.
///
/// Production builds skip this file entirely (`#if DEBUG`).
enum UITestWindowFrameHandler {

    private static let argumentPrefix = "--ui-test-window="

    /// Retained observer token so the frame is pinned as soon as a document
    /// window becomes key (the seed handler opens the window asynchronously,
    /// after this runs at launch). `nonisolated(unsafe)` matches the sibling
    /// `UITestSeedHandler.didOpen`: mutation is serialized on the main queue
    /// (the observer is registered with `queue: .main`), so it is race-free.
    private nonisolated(unsafe) static var observer: NSObjectProtocol?

    /// Called at app launch. If a `--ui-test-window` arg is present and valid,
    /// registers a one-shot observer that pins the first document window's frame
    /// once it becomes key; otherwise no-ops so normal launches are unaffected.
    @MainActor
    static func applyIfRequested() {
        guard let size = windowSize(from: CommandLine.arguments) else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow, window.isDocumentWindow else { return }
            MainActor.assumeIsolated { pin(window, to: size) }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }

    /// Sets `window`'s frame to `size` anchored at the top-left of its screen's
    /// visible area, so the whole window is guaranteed on-screen. `NSScreen`
    /// uses a bottom-left origin, so the top-left anchor is `maxY - height`.
    @MainActor
    private static func pin(_ window: NSWindow, to size: CGSize) {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let origin = NSPoint(x: visible.minX, y: visible.maxY - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Parses the launch arguments for `--ui-test-window=<W>x<H>` and returns the
    /// size. Returns `nil` when the argument is absent or malformed (missing a
    /// half, non-numeric, or a non-positive dimension). Pure so it can be
    /// unit-tested without launching the app.
    static func windowSize(from arguments: [String]) -> CGSize? {
        for arg in arguments where arg.hasPrefix(argumentPrefix) {
            let parts = String(arg.dropFirst(argumentPrefix.count)).split(separator: "x")
            guard parts.count == 2,
                  let width = Double(parts[0]), let height = Double(parts[1]),
                  width > 0, height > 0 else { return nil }
            return CGSize(width: width, height: height)
        }
        return nil
    }
}

private extension NSWindow {
    /// A document window carries a non-nil `windowController` with a
    /// `document`; the app's AppKit start-page window and panels do not.
    var isDocumentWindow: Bool {
        windowController?.document != nil
    }
}
#endif
