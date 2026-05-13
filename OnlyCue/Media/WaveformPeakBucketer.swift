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
}
