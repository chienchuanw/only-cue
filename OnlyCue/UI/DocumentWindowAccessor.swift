import AppKit
import SwiftUI

/// Bridges the SwiftUI document view to its host `NSWindow` and intercepts the
/// window's close button so it collapses to the Mini Player instead of tearing
/// the document down while the Mini Player is visible (#743).
struct DocumentWindowAccessor: NSViewRepresentable {

    let onResolve: (NSWindow) -> Void
    let shouldCollapseOnClose: () -> Bool
    let onCollapse: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolve(window)
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldCollapse: shouldCollapseOnClose, onCollapse: onCollapse)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let shouldCollapse: () -> Bool
        private let onCollapse: () -> Void
        /// The delegate that was installed before we took over (typically SwiftUI's
        /// DocumentGroup delegate). We forward any selector we don't implement to it
        /// so that unsaved-changes prompts and other AppKit-DocumentGroup callbacks
        /// keep working on the normal-close path.
        weak var previousDelegate: NSWindowDelegate?

        init(shouldCollapse: @escaping () -> Bool, onCollapse: @escaping () -> Void) {
            self.shouldCollapse = shouldCollapse
            self.onCollapse = onCollapse
        }

        func attach(to window: NSWindow) {
            previousDelegate = window.delegate   // capture BEFORE replacing
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldCollapse() else {
                // Normal close — let the prior delegate (DocumentGroup) decide,
                // so unsaved-changes save prompts keep working.
                return previousDelegate?.windowShouldClose?(sender) ?? true
            }
            onCollapse()   // hide instead of closing
            return false
        }

        // MARK: - Delegate forwarding

        /// Advertise selectors that our `previousDelegate` responds to, so AppKit
        /// routes those messages through `forwardingTarget(for:)` to the prior delegate.
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (previousDelegate?.responds(to: aSelector) ?? false)
        }

        /// For any selector we do NOT implement ourselves, forward to the prior
        /// delegate. `windowShouldClose` is implemented above, so it never reaches
        /// here — all other DocumentGroup delegate methods do.
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            previousDelegate
        }
    }
}
