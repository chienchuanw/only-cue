import Foundation

/// Downsamples a high-resolution peak array to the number of horizontal pixels
/// currently on screen, taking the maximum magnitude within each pixel bucket so
/// transients aren't averaged away — the rendering trick DAWs use to keep the
/// waveform crisp at any zoom.
enum WaveformPeakBucketer {

    /// - Parameters:
    ///   - peaks: source magnitudes in `0...1`.
    ///   - width: target column count, typically the on-screen pixel width.
    /// - Returns: at most `width` magnitudes, each the max of its bucket.
    ///   Returns the input unchanged when `width >= peaks.count`, and `[]` when
    ///   `peaks` is empty or `width <= 0`.
    static func bucket(peaks: [Float], into width: Int) -> [Float] {
        guard !peaks.isEmpty, width > 0 else { return [] }
        guard width < peaks.count else { return peaks }

        let perBucket = Int((Double(peaks.count) / Double(width)).rounded(.up))
        var result: [Float] = []
        result.reserveCapacity(width)
        var start = 0
        for _ in 0..<width {
            guard start < peaks.count else { break }
            let end = min(start + perBucket, peaks.count)
            result.append(peaks[start..<end].max() ?? 0)
            start = end
        }
        return result
    }

    /// Downsamples like `bucket`, but takes each bucket's **RMS** (√mean of
    /// squares) instead of its max — the loudness-faithful body of the dual
    /// envelope (#734), so a brickwall master's overview keeps visible dynamics
    /// instead of collapsing to a solid block (#632). Pairs with `bucket` (max),
    /// which stays the transient outline. Same edge-case contract as `bucket`.
    static func bucketRMS(_ values: [Float], into width: Int) -> [Float] {
        guard !values.isEmpty, width > 0 else { return [] }
        guard width < values.count else { return values }

        let perBucket = Int((Double(values.count) / Double(width)).rounded(.up))
        var result: [Float] = []
        result.reserveCapacity(width)
        var start = 0
        for _ in 0..<width {
            guard start < values.count else { break }
            let end = min(start + perBucket, values.count)
            let slice = values[start..<end]
            let meanSquare = slice.reduce(Float(0)) { $0 + $1 * $1 } / Float(slice.count)
            result.append(meanSquare.squareRoot())
            start = end
        }
        return result
    }
}
