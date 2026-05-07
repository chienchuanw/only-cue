import Foundation

struct ScrubController {

    struct State: Equatable {
        let resumeOnRelease: Bool
        let originalTime: TimeInterval
        var scrubTime: TimeInterval
    }

    private(set) var state: State?

    mutating func begin(originalTime: TimeInterval, isPlaying: Bool) {
        state = State(
            resumeOnRelease: isPlaying,
            originalTime: originalTime,
            scrubTime: originalTime
        )
    }

    mutating func update(dx: CGFloat, width: CGFloat, duration: TimeInterval) {
        guard var current = state else { return }
        current.scrubTime = CueMarkersGeometry.time(
            originalTime: current.originalTime,
            dx: dx,
            width: width,
            duration: duration
        )
        state = current
    }

    mutating func end() -> State? {
        let finished = state
        state = nil
        return finished
    }
}
