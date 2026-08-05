import AppKit
import SwiftUI

/// Whether a broadcast menu notification belongs to this window.
///
/// `NotificationCenter.default.post` reaches every open `DocumentView`, so a
/// workspace preset would otherwise rearrange every window at once — against
/// spec decision 9, which makes layout a per-window property.
enum WindowScope {

    /// - Parameter openWindowCount: how many document windows exist. With
    ///   exactly one, key-window state is ignored: a sheet or an inspector
    ///   panel can hold key while the document window is plainly the target,
    ///   and refusing then would make the menu item look dead.
    static func shouldHandle(isFrontmost: Bool, openWindowCount: Int) -> Bool {
        guard openWindowCount > 0 else { return false }
        if openWindowCount == 1 { return true }
        return isFrontmost
    }
}

/// Publishes whether the hosting window is currently key.
struct FrontmostWindowGate: ViewModifier {

    @Binding var isFrontmost: Bool
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window = $0; refresh() })
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            ) { _ in refresh() }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            ) { _ in refresh() }
    }

    private func refresh() {
        isFrontmost = window?.isKeyWindow ?? false
    }

    /// Zero-size probe that hands back the hosting `NSWindow`. SwiftUI has no
    /// public accessor for it on macOS 14.
    private struct WindowReader: NSViewRepresentable {
        let onResolve: (NSWindow?) -> Void

        func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { onResolve(view.window) }
        }
    }
}

extension View {
    func frontmostWindowGate(isFrontmost: Binding<Bool>) -> some View {
        modifier(FrontmostWindowGate(isFrontmost: isFrontmost))
    }
}
