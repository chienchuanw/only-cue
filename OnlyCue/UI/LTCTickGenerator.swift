import CoreGraphics
import Foundation

struct LTCTick: Equatable {
    let xPosition: CGFloat
    let label: String
    let isMajor: Bool
}

/// Builds the array of TC tick marks the main-view LTC strip renders. Given a
/// clip's duration, the project framerate, the clip's start TC (in frames),
/// the chosen `bucketSeconds`, and the strip's `contentWidth`, returns one
/// `LTCTick` per `bucketSeconds`-spaced step. Labels are `HH:MM:SS` (no
/// frames — too noisy at the strip's zoom); every fifth tick is "major" (used
/// by the renderer to draw a taller mark).
enum LTCTickGenerator {

    static func ticks(
        duration: TimeInterval,
        framerate: SMPTEFramerate,
        startTimecodeFrames: Int,
        bucketSeconds: Int,
        contentWidth: CGFloat
    ) -> [LTCTick] {
        guard duration > 0, contentWidth > 0, bucketSeconds > 0 else { return [] }
        let pxPerSecond = contentWidth / CGFloat(duration)
        var out: [LTCTick] = []
        var second = 0
        var stepIndex = 0
        while Double(second) <= duration + 0.001 {
            let frames = startTimecodeFrames + second * framerate.framesPerSecond
            let timecode = Timecode(frameCount: frames, rate: framerate)
            out.append(LTCTick(
                xPosition: CGFloat(second) * pxPerSecond,
                label: Self.formatHMS(timecode),
                isMajor: stepIndex % 5 == 0
            ))
            second += bucketSeconds
            stepIndex += 1
        }
        return out
    }

    private static func formatHMS(_ timecode: Timecode) -> String {
        String(format: "%02d:%02d:%02d", timecode.hours, timecode.minutes, timecode.seconds)
    }
}
