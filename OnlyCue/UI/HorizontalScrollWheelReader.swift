import AppKit
import SwiftUI

/// Hosts SwiftUI content and reports horizontal scroll-wheel deltas, so the
/// waveform can still be scrolled manually now that it renders via a continuous
/// pixel offset instead of a `ScrollView` (#675). Only `scrollWheel` is
/// intercepted — clicks / drags pass straight through to the hosted content, so
/// the seek surface, cue markers, and magnifier gestures are unaffected.
struct HorizontalScrollWheelReader<Content: View>: NSViewRepresentable {

    /// Horizontal scroll delta in points (macOS natural-scroll sign). Positive =
    /// two-finger swipe right.
    let onScroll: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> ScrollWheelHostingView<Content> {
        let view = ScrollWheelHostingView(rootView: content())
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelHostingView<Content>, context: Context) {
        nsView.onScroll = onScroll
        nsView.rootView = content()
    }
}

/// `NSHostingView` subclass that forwards horizontal scroll-wheel deltas. Because
/// it *is* the host of the SwiftUI content, a scroll over the content reaches it
/// (SwiftUI views without a `ScrollView` don't consume scroll), while mouse
/// clicks still dispatch normally into the hosted content.
final class ScrollWheelHostingView<Content: View>: NSHostingView<Content> {

    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        // Horizontal intent: a horizontal swipe (`scrollingDeltaX`), or a
        // Shift-held vertical swipe (macOS convention for horizontal scroll).
        let dx: CGFloat
        if event.scrollingDeltaX != 0 {
            dx = event.scrollingDeltaX
        } else if event.modifierFlags.contains(.shift) {
            dx = event.scrollingDeltaY
        } else {
            dx = 0
        }
        if dx != 0 {
            onScroll?(dx)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
