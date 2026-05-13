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

    var isPlaying: Bool { rate > 0 }

    @ObservationIgnored
    let player: AVPlayer

    @ObservationIgnored
    private var timeObserver: Any?

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
        observeTime()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func load(asset: AVAsset) async {
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        rate = 0
        currentTime = 0
        if let cmDuration = try? await asset.load(.duration) {
            duration = CMTimeGetSeconds(cmDuration)
        }
    }

    func unload() async {
        player.pause()
        player.replaceCurrentItem(with: nil)
        rate = 0
        currentTime = 0
        duration = 0
    }

    func play() {
        player.play()
        rate = player.rate
    }

    func pause() {
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
