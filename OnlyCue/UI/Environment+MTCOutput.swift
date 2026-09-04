import SwiftUI

private struct MTCOutputKey: EnvironmentKey {
    /// `nil` when no `MTCOutputHost` is above the reader — previews and isolated
    /// views then render without the pill instead of trapping, which is why this
    /// is an optional `@Environment` value rather than an `@EnvironmentObject`.
    static let defaultValue: MTCOutput? = nil
}

extension EnvironmentValues {
    /// The document window's live MTC generator, injected by `MTCOutputHost` so
    /// the transport pill can show what the generator is doing without threading
    /// the object down through `ModeAwareInspector` and `CueListPane`.
    var mtcOutput: MTCOutput? {
        get { self[MTCOutputKey.self] }
        set { self[MTCOutputKey.self] = newValue }
    }
}
