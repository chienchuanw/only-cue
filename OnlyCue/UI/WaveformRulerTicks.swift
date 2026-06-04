import CoreGraphics
import Foundation

/// Pure tick math for the waveform time-ruler (Figma `318:1271`). Evenly-spaced
/// ticks across `contentWidth`, with the bucket chosen by `LTCTickInterval` so
/// neighbouring labels never crowd, and zero-padded `MM:SS` (or `H:MM:SS` past
/// an hour) labels on every fifth (major) tick. Framerate-independent — the
/// buckets are whole seconds, so no `Timecode` is needed.
enum WaveformRulerTicks {

    struct Tick: Equatable {
        let x: CGFloat
        let label: String
        let isMajor: Bool
    }

    static func ticks(duration: TimeInterval, contentWidth: CGFloat) -> [Tick] {
        guard duration > 0, contentWidth > 0 else { return [] }
        let pxPerSecond = contentWidth / CGFloat(duration)
        let bucket = LTCTickInterval.pick(secondsVisible: duration, pxPerSecond: pxPerSecond)
        var out: [Tick] = []
        var second = 0
        var step = 0
        while Double(second) <= duration + 0.001 {
            out.append(Tick(
                x: CGFloat(second) * pxPerSecond,
                label: label(forSeconds: second),
                isMajor: step % 5 == 0
            ))
            second += bucket
            step += 1
        }
        return out
    }

    private static func label(forSeconds seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
