import AppKit
import SwiftUI

/// Reads and writes the `NavigationSplitView` sidebar's width.
///
/// SwiftUI gives the sidebar a native drag within
/// `.navigationSplitViewColumnWidth(min:ideal:max:)` but no way to read the
/// dragged value back or to set it when a workspace preset is applied. This
/// probe closes both gaps: a zero-size `NSView` placed in the sidebar walks up
/// its superview chain to the hosting `NSSplitView` (seven levels up, delegate
/// `SwiftUI.NavigationSplitViewController`) and calls
/// `setPosition(_:ofDividerAt:)`.
///
/// It writes the divider position and **nothing else** — no delegate is
/// installed and no constraint participation changes — so the #617 mechanism
/// (an `NSSplitView` in the *detail* column inflating the window minimum) has
/// nothing to re-engage. The spike measured `contentMinSize` at 1149 with this
/// in place, well under the 1280pt design width.
struct SidebarWidthBridge: NSViewRepresentable {

    /// The width a preset wants applied, or nil when the user is in charge.
    var targetWidth: CGFloat?
    /// Reports the sidebar's live width after every layout pass.
    var onMeasure: (CGFloat) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onMeasure = onMeasure
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onMeasure = onMeasure
        view.apply(targetWidth: targetWidth)
    }

    // MARK: - Arithmetic (unit-tested)

    /// The constant gap between the SwiftUI-reported sidebar width and the
    /// `NSSplitView` divider position. Derived from an observed pair, never
    /// hardcoded — the spike saw 8pt consistently, but that is SwiftUI's
    /// internal inset and is not contractual.
    static func inset(measuredWidth: CGFloat, dividerPosition: CGFloat) -> CGFloat {
        dividerPosition - measuredWidth
    }

    /// The divider position that yields `targetWidth` of visible sidebar.
    static func dividerPosition(forTargetWidth targetWidth: CGFloat, inset: CGFloat?) -> CGFloat {
        targetWidth + (inset ?? 0)
    }

    // MARK: - Probe

    final class ProbeView: NSView {

        var onMeasure: ((CGFloat) -> Void)?

        /// The inset derived from the most recent (measured width, divider
        /// position) pair. nil until the first layout pass.
        private var observedInset: CGFloat?
        /// The last target actually applied, so a re-render does not fight the
        /// user's subsequent drag by re-applying the same value every frame.
        private var appliedTarget: CGFloat?

        /// The hosting split view, or nil if SwiftUI's view hierarchy changed
        /// shape. Everything here degrades to a no-op in that case — the
        /// sidebar keeps its native drag and only preset application is lost.
        private var hostingSplitView: NSSplitView? {
            var candidate: NSView? = superview
            while let view = candidate {
                if let split = view as? NSSplitView { return split }
                candidate = view.superview
            }
            return nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            measure()
        }

        override func layout() {
            super.layout()
            measure()
        }

        private func measure() {
            guard let split = hostingSplitView,
                  let sidebar = split.arrangedSubviews.first
            else { return }
            let position = sidebar.frame.width
            // The probe sits inside the sidebar, so its own enclosing scroll /
            // content view reports the *visible* width SwiftUI lays out to.
            let measured = enclosingContentWidth ?? position
            observedInset = SidebarWidthBridge.inset(
                measuredWidth: measured,
                dividerPosition: position
            )
            onMeasure?(measured)
        }

        private var enclosingContentWidth: CGFloat? {
            var candidate: NSView? = superview
            while let view = candidate {
                if view is NSSplitView { return nil }
                if view.frame.width > 0 { return view.frame.width }
                candidate = view.superview
            }
            return nil
        }

        func apply(targetWidth: CGFloat?) {
            guard let targetWidth, targetWidth != appliedTarget else {
                if targetWidth == nil { appliedTarget = nil }
                return
            }
            guard let split = hostingSplitView, !split.arrangedSubviews.isEmpty else { return }
            appliedTarget = targetWidth
            let position = SidebarWidthBridge.dividerPosition(
                forTargetWidth: targetWidth,
                inset: observedInset
            )
            split.setPosition(position, ofDividerAt: 0)
        }
    }
}

extension View {
    /// Attaches the sidebar width probe as a zero-size background. A background
    /// (not an overlay or a sibling) so it can never intercept a click or take
    /// part in layout.
    func sidebarWidthBridge(
        targetWidth: CGFloat?,
        onMeasure: @escaping (CGFloat) -> Void
    ) -> some View {
        background(
            SidebarWidthBridge(targetWidth: targetWidth, onMeasure: onMeasure)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
