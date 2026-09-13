import SwiftUI

private struct LTCOutputKey: EnvironmentKey {
    /// `nil` when no `LTCOutputHost` is above the reader — previews and isolated
    /// views then render without the pill instead of trapping, which is why this
    /// is an optional `@Environment` value rather than an `@EnvironmentObject`.
    static let defaultValue: LTCAudioOutput? = nil
}

extension EnvironmentValues {
    /// The document window's live LTC engine, injected by `LTCOutputHost` so the
    /// transport pill can show what the engine is doing without threading the
    /// object down through `ModeAwareInspector` and `CueListPane` (#796).
    var ltcOutput: LTCAudioOutput? {
        get { self[LTCOutputKey.self] }
        set { self[LTCOutputKey.self] = newValue }
    }
}
