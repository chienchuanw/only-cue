import Foundation

/// Transitional shim — v11 dropped `MediaItem.tempoMap` (per-cue tempo replaces
/// the per-item map). Read sites that haven't yet been swapped to the new
/// derived grid still compile by reading an empty `TempoMap` here; writes are
/// silently dropped. The Tempo Map sheet and remaining call sites are removed
/// in Leaf 5 (issue #248); this file disappears with them.
extension MediaItem {
    var tempoMap: TempoMap {
        get { TempoMap() }
        set { _ = newValue }
    }
}
