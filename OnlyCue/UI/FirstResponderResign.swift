import AppKit
import SwiftUI

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

/// SwiftUI view modifier that installs a window-scoped local `NSEvent` monitor
/// for `.leftMouseDown` events. On every event, asks `FirstResponderResign`
/// whether the click should resign the active text first responder. If yes,
/// calls `window.makeFirstResponder(nil)`, which propagates back through
/// SwiftUI's `@FocusState` and triggers the existing `commitOnFocusLeave`
/// machinery in `CueRowView` (inline edits for Number / Name / Fade) and the
/// modal sheets hosted by `CueListPane` (Notes / Tempo). Returns the event
/// unchanged so normal click handling proceeds.
struct FirstResponderResignOnOutsideClick: ViewModifier {
    func body(content: Content) -> some View {
        content.background(FirstResponderResignMonitor())
    }
}

/// `NSViewRepresentable` whose only job is to install / tear down the AppKit
/// event monitor used by `FirstResponderResignOnOutsideClick`. Lives at file
/// scope (not nested inside the modifier) to keep `Coordinator` within
/// SwiftLint's `nesting` cap.
private struct FirstResponderResignMonitor: NSViewRepresentable {

    final class Coordinator {
        var monitor: Any?
        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.monitor == nil else { return }
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown
        ) { event in
            guard
                let window = event.window,
                let firstResponder = window.firstResponder as? NSText
            else { return event }

            let frame = firstResponder.convert(firstResponder.bounds, to: nil)
            let shouldResign = FirstResponderResign.shouldResign(
                clickLocationInWindow: event.locationInWindow,
                firstResponderFrameInWindow: frame,
                firstResponderIsText: true
            )
            if shouldResign {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }
}

extension View {
    /// Installs a window-scoped left-mouse-down monitor that resigns the
    /// first responder when the user clicks outside an active text field.
    /// Apply once at the document window's root.
    func resignFirstResponderOnOutsideClick() -> some View {
        modifier(FirstResponderResignOnOutsideClick())
    }
}
