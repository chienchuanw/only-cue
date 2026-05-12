import Foundation
import os

/// Lock-protected single-producer / single-consumer FIFO of interleaved stereo
/// float samples (`L, R, L, R, …`). Hands the media's program audio from the
/// realtime `MTAudioProcessingTap` callback (`ProgramAudioTap`) to
/// `LTCAudioOutput`'s buffer pump. Fixed capacity in frames; an overflowing
/// `push` drops the oldest frames (glitch the past, never block the tap), an
/// underrunning `drain` zero-fills the tail. A "frame" is one `(L, R)` pair —
/// two samples.
///
/// Not `@MainActor` — both ends run off the main actor. Pure logic, unit-tested.
final class ProgramAudioRingBuffer: @unchecked Sendable {

    private let capacityFrames: Int
    private var storage: [Float]          // capacityFrames * 2 samples
    private var head = 0                  // index (in frames) of the next frame to read
    private var count = 0                 // frames currently buffered
    private let lock = OSAllocatedUnfairLock()

    init(capacityFrames: Int) {
        let cap = max(1, capacityFrames)
        self.capacityFrames = cap
        storage = [Float](repeating: 0, count: cap * 2)
    }

    /// Append interleaved stereo samples. A non-even-length input is rejected
    /// wholesale (it can't be split into frames). Keeps at most the newest
    /// `capacityFrames` frames of the combined buffer.
    func push(interleavedStereo samples: [Float]) {
        guard !samples.isEmpty, samples.count.isMultiple(of: 2) else { return }
        let incomingFrames = samples.count / 2
        lock.withLock {
            // Only the last `capacityFrames` of the incoming frames can survive.
            let keepFrames = min(incomingFrames, capacityFrames)
            let srcFrameStart = incomingFrames - keepFrames

            // Make room: if buffering `keepFrames` more would exceed capacity,
            // drop that many of the oldest already-buffered frames.
            let overflow = (count + keepFrames) - capacityFrames
            if overflow > 0 {
                head = (head + overflow) % capacityFrames
                count -= overflow
            }

            let writeStart = (head + count) % capacityFrames
            for offset in 0..<keepFrames {
                let dstFrame = (writeStart + offset) % capacityFrames
                let src = (srcFrameStart + offset) * 2
                storage[dstFrame * 2] = samples[src]
                storage[dstFrame * 2 + 1] = samples[src + 1]
            }
            count += keepFrames
        }
    }

    /// Return exactly `frameCount` interleaved stereo frames; zero-fills any tail
    /// not backed by buffered data.
    func drain(frameCount: Int) -> [Float] {
        guard frameCount > 0 else { return [] }
        return lock.withLock {
            var out = [Float](repeating: 0, count: frameCount * 2)
            let take = min(frameCount, count)
            for offset in 0..<take {
                let srcFrame = (head + offset) % capacityFrames
                out[offset * 2] = storage[srcFrame * 2]
                out[offset * 2 + 1] = storage[srcFrame * 2 + 1]
            }
            head = (head + take) % capacityFrames
            count -= take
            return out
        }
    }

    func flush() {
        lock.withLock {
            head = 0
            count = 0
        }
    }
}
