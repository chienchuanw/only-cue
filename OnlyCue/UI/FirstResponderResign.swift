import AppKit

/// Pure-logic predicate for "should we resign the active text first responder
/// because the user clicked outside its frame?"
///
/// Extracted so the hit-test logic can be unit-tested without spinning up an
/// `NSWindow`. Consumed by `FirstResponderResignOnOutsideClick`'s window-level
/// `NSEvent.addLocalMonitorForEvents` callback.
///
/// - `firstResponderIsText` gates the rule to actual text-input first responders
///   (`NSText` / `NSTextField` / `NSTextView`); we must NOT yank focus from
///   buttons or other focusable controls.
/// - The frame check uses `NSRect.contains`, which is inclusive on the edges —
///   a click landing exactly on the frame boundary counts as inside.
enum FirstResponderResign {
    static func shouldResign(
        clickLocationInWindow: NSPoint,
        firstResponderFrameInWindow: NSRect,
        firstResponderIsText: Bool
    ) -> Bool {
        guard firstResponderIsText else { return false }
        return !firstResponderFrameInWindow.contains(clickLocationInWindow)
    }
}
