import CoreGraphics

/// Picks the smallest seconds bucket from `[1, 5, 15, 30, 60]` such that each
/// tick label has at least `minPxPerLabel` horizontal pixels — so neighbour
/// labels never visually overlap at the chosen zoom. Pure helper consumed by
/// `LTCTickGenerator` and the main-view LTC strip. Zero / negative
/// `pxPerSecond` falls back to the coarsest bucket so the caller still gets a
/// useful interval at extreme zoom-outs.
enum LTCTickInterval {

    static let buckets: [Int] = [1, 5, 15, 30, 60]
    static let minPxPerLabel: CGFloat = 56

    static func pick(secondsVisible: Double, pxPerSecond: CGFloat) -> Int {
        guard pxPerSecond > 0 else { return buckets.last ?? 60 }
        for bucket in buckets where CGFloat(bucket) * pxPerSecond >= minPxPerLabel {
            return bucket
        }
        return buckets.last ?? 60
    }
}
