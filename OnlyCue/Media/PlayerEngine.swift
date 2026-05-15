import AVFoundation
import Observation
import QuartzCore

@Observable
@MainActor
final class PlayerEngine {

    private(set) var currentTime: TimeInterval = 0
    /// `CACurrentMediaTime()` captured when `currentTime` was last updated by
    /// the periodic observer (or `seek`). `PlayheadInterpolator` slides the
    /// rendered playhead forward from this anchor between observer ticks.
    private(set) var currentTimeObservedAt: TimeInterval = CACurrentMediaTime()
    private(set) var rate: Float = 0
    private(set) var duration: TimeInterval = 0

    /// User-facing playback rate. Range `[0.1, 3.0]`, snapped to 0.1.
    /// Distinct from `rate`, which reflects `AVPlayer.rate` (0 when paused).
    /// `playbackRate` is the rate `play()` will apply to the player.
    private(set) var playbackRate: Float = 1.0

    var isPlaying: Bool { rate > 0 }

    @ObservationIgnored
    let player: AVPlayer

    @ObservationIgnored
    private var timeObserver: Any?

    /// Last user intent: `true` between `play()` and the next `pause()` /
    /// `unload()`. `setPlaybackRate(_:)` pushes the new rate to `AVPlayer.rate`
    /// while this is `true`, regardless of whether the player has actually
    /// started yet (on slower hosts `player.rate` lags behind intent).
    @ObservationIgnored
    private var wantsToPlay = false

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
        observeTime()
    }

#if DEBUG
    /// Test seam — directly sets `currentTime` without an `AVPlayer` round-trip.
    /// Production code must go through `seek(to:)` instead.
    func debugSetCurrentTime(_ seconds: TimeInterval) {
        currentTime = seconds
        currentTimeObservedAt = CACurrentMediaTime()
    }
#endif

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func load(asset: AVAsset) async {
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        player.replaceCurrentItem(with: item)
        rate = 0
        currentTime = 0
        if let cmDuration = try? await asset.load(.duration) {
            duration = CMTimeGetSeconds(cmDuration)
        }
    }

    func unload() async {
        wantsToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        rate = 0
        currentTime = 0
        duration = 0
    }

    func play() {
        wantsToPlay = true
        player.play()
        // Set after play() so AVPlayer's timeControlStatus flips first; otherwise
        // it can snap rate back to 1.0.
        player.rate = playbackRate
        rate = player.rate
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        rate = player.rate
    }

    func toggle() {
        if rate > 0 { pause() } else { play() }
    }

    /// Mute / unmute the player's own audio output. The LTC output path uses this
    /// to silence program audio on `AVPlayer` while it is re-routed through the
    /// LTC `AVAudioEngine`'s Track channels. Idempotent.
    func setAudioMuted(_ muted: Bool) {
        player.volume = muted ? 0 : 1
    }

    func seek(to seconds: TimeInterval) async {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        currentTimeObservedAt = CACurrentMediaTime()
    }

    // MARK: - Playback rate

    /// Allowed playback rate range, inclusive.
    static let playbackRateRange: ClosedRange<Float> = 0.1...3.0
    /// Snap step for `setPlaybackRate(_:)`.
    static let playbackRateStep: Float = 0.1

    /// Set the playback rate, clamped to `playbackRateRange` and snapped to the
    /// nearest `playbackRateStep`. If the player is currently playing, the live
    /// `AVPlayer.rate` is updated to match.
    ///
    /// LTC interlock is enforced by callers (the keymap action + menu item);
    /// this method does not consult LTC state so unit tests can drive the rate
    /// without standing up a routing store.
    func setPlaybackRate(_ rate: Float) {
        let range = Self.playbackRateRange
        let step = Self.playbackRateStep
        let clamped = min(max(rate, range.lowerBound), range.upperBound)
        let snapped = (clamped / step).rounded() * step
        playbackRate = min(max(snapped, range.lowerBound), range.upperBound)
        // Push to AVPlayer whenever the user has called play() — checking
        // `player.rate > 0` is unreliable because rate lags intent on slow hosts
        // (AVPlayer.rate stays at 0 while the item is still buffering).
        if wantsToPlay {
            player.rate = playbackRate
        }
    }

    /// Increment / decrement by `delta` (typically ±0.1). Clamps via `setPlaybackRate(_:)`.
    func nudgePlaybackRate(by delta: Float) {
        setPlaybackRate(playbackRate + delta)
    }

    /// Reset to 1.0×.
    func resetPlaybackRate() {
        setPlaybackRate(1.0)
    }

    private func observeTime() {
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                self.currentTimeObservedAt = CACurrentMediaTime()
                self.rate = self.player.rate
            }
        }
    }
}
