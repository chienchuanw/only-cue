import Foundation

/// Encodes a cue's absolute timecode for a grandMA2 `Assign … /TrigTime=`
/// command (#683, Approach A). The value is decimal seconds on the project frame
/// grid — the console quantizes it to its slot's timecode format (1/100 s, 24,
/// 25 or 30 fps). Emitting seconds (not a physical frame count under a format
/// label) is what lets the command path avoid the drop-frame hazard the XML
/// timecode path carried.
enum MA2TrigTime {

    /// Absolute time of `cueTime` (seconds into the clip) as decimal seconds,
    /// snapped to the project frame grid and offset by the clip's start timecode.
    static func seconds(cueTime: TimeInterval, startTimecodeFrames: Int, framerate: SMPTEFramerate) -> Double {
        let fps = Double(framerate.framesPerSecond)
        let absFrames = startTimecodeFrames + Int((cueTime * fps).rounded())
        return Double(absFrames) / fps
    }

    /// The `/TrigTime=` argument: `seconds(...)` as a trimmed decimal string
    /// (`"5"`, `"2.133333"`).
    static func command(cueTime: TimeInterval, startTimecodeFrames: Int, framerate: SMPTEFramerate) -> String {
        let value = seconds(cueTime: cueTime, startTimecodeFrames: startTimecodeFrames, framerate: framerate)
        var text = String(format: "%.6f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
