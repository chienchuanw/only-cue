import Foundation

/// An SMPTE timecode `HH:MM:SS:FF` (`;` between SS and FF for drop-frame) at a
/// given `SMPTEFramerate`.
///
/// Stores the displayed components and the rate; `frameCount` and `totalSeconds`
/// are derived. For drop-frame (`fps30drop`) the components↔count mapping
/// follows the standard rule — frame numbers `00` and `01` are skipped at the
/// top of every minute except every tenth minute — so `frameCount` is the
/// *actual* number of frames elapsed since `00:00:00:00`, which is what an LTC
/// signal and `PlayerEngine.currentTime` care about; the components are labels.
struct Timecode: Equatable, Hashable, Sendable {

    let rate: SMPTEFramerate
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int

    /// Returns `nil` if any component is out of range for `rate`, or — for
    /// drop-frame — if the components name a frame number the counting rule
    /// skips (`00:MM:00;00` / `00:MM:00;01` for a non-tenth minute `MM`).
    init?(hours: Int, minutes: Int, seconds: Int, frames: Int, rate: SMPTEFramerate) {
        guard (0..<24).contains(hours),
              (0..<60).contains(minutes),
              (0..<60).contains(seconds),
              (0..<rate.framesPerSecond).contains(frames) else { return nil }
        if rate.isDropFrame, seconds == 0, frames < 2, minutes % 10 != 0 { return nil }
        self.rate = rate
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
    }

    /// Build from a count of frames elapsed since `00:00:00:00`. A negative
    /// count clamps to zero; a count past `24:00:00:00` wraps modulo one day.
    init(frameCount: Int, rate: SMPTEFramerate) {
        var count = max(0, frameCount) % Self.framesPerDay(rate)
        if rate.isDropFrame {
            // Standard reverse drop-frame conversion (30 fps base).
            let framesPer10Min = 17982   // 10 * 60 * 30 − 18
            let framesPerMin = 1798      // 60 * 30 − 2
            let tens = count / framesPer10Min
            let within = count % framesPer10Min
            count += 18 * tens
            if within >= 2 { count += 2 * ((within - 2) / framesPerMin) }
        }
        let fps = rate.framesPerSecond
        self.frames = count % fps
        self.seconds = (count / fps) % 60
        self.minutes = (count / fps / 60) % 60
        self.hours = (count / fps / 60 / 60) % 24
        self.rate = rate
    }

    /// Build from a wall-clock offset, rounding to the nearest frame.
    init(totalSeconds: TimeInterval, rate: SMPTEFramerate) {
        let frames = max(0, (totalSeconds * Double(rate.framesPerSecond)).rounded())
        self.init(frameCount: Int(frames), rate: rate)
    }

    /// Frames elapsed since `00:00:00:00` (drop-frame aware).
    var frameCount: Int {
        let fps = rate.framesPerSecond
        let base = ((hours * 60 + minutes) * 60 + seconds) * fps + frames
        guard rate.isDropFrame else { return base }
        let totalMinutes = hours * 60 + minutes
        return base - 2 * (totalMinutes - totalMinutes / 10)
    }

    /// Wall-clock seconds since `00:00:00:00`. Nominal — `fps30drop` divides by
    /// 30.0, not 29.97 (v1 simplification).
    var totalSeconds: TimeInterval {
        Double(frameCount) / Double(rate.framesPerSecond)
    }

    var displayString: String {
        let separator = rate.isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, separator, frames)
    }

    /// Parse a `HH:MM:SS:FF` (or `HH:MM:SS;FF`) string for `rate`. Any of
    /// `:`/`;`/`.`/`,` and whitespace separate the four fields; leading/trailing
    /// whitespace is ignored. Returns `nil` unless it's exactly four
    /// non-negative integer fields whose values are in range for `rate` (and,
    /// for drop-frame, not a frame number the counting rule skips). The
    /// `;`-vs-`:` separator is punctuation only — drop-frame-ness comes from
    /// `rate`.
    static func parse(_ string: String, rate: SMPTEFramerate) -> Self? {
        let separators = CharacterSet(charactersIn: ":;,. \t")
        let fields = string.components(separatedBy: separators).filter { !$0.isEmpty }
        guard fields.count == 4,
              let hours = Int(fields[0]), let minutes = Int(fields[1]),
              let seconds = Int(fields[2]), let frames = Int(fields[3]) else { return nil }
        return Self(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate)
    }

    private static func framesPerDay(_ rate: SMPTEFramerate) -> Int {
        let nonDrop = 24 * 60 * 60 * rate.framesPerSecond
        guard rate.isDropFrame else { return nonDrop }
        let minutesPerDay = 24 * 60
        return nonDrop - 2 * (minutesPerDay - minutesPerDay / 10)
    }
}
