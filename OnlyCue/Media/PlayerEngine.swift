import AVFoundation
import Observation

@Observable
@MainActor
final class PlayerEngine {

    private(set) var currentTime: TimeInterval = 0
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
    }

    private func observeTime() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                self.rate = self.player.rate
            }
        }
    }
}
