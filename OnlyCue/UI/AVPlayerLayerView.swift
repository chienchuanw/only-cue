import AVFoundation
import AppKit
import SwiftUI

struct AVPlayerLayerView: NSViewRepresentable {

    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostingView {
        let view = PlayerHostingView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerHostingView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }
}

final class PlayerHostingView: NSView {

    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
