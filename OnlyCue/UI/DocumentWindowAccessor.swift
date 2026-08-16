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

        init(shouldCollapse: @escaping () -> Bool, onCollapse: @escaping () -> Void) {
            self.shouldCollapse = shouldCollapse
            self.onCollapse = onCollapse
        }

        func attach(to window: NSWindow) { window.delegate = self }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldCollapse() else { return true }  // default close (document teardown)
            onCollapse()                                  // hide instead
            return false
        }
    }
}
