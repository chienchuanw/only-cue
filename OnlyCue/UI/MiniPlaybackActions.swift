import Foundation

/// The single Mini Player playback-action seam (#743). Both the Mini Player's
/// on-screen buttons and its keyboard monitor route through this, so button and
/// keyboard behavior cannot drift. Every body reuses an existing seam.
@MainActor
struct MiniPlaybackActions {

    let engine: PlayerEngine
    let document: CueListDocument
    let context: MiniPlayerContext
    let ltcEnabled: Bool

    private var seekTaskBox: SeekTaskBox

    init(engine: PlayerEngine, document: CueListDocument, context: MiniPlayerContext, ltcEnabled: Bool, seekTaskBox: SeekTaskBox) {
        self.engine = engine
        self.document = document
        self.context = context
        self.ltcEnabled = ltcEnabled
        self.seekTaskBox = seekTaskBox
    }

    func perform(_ action: MiniPlaybackAction) {
        switch action {
        case .playPause: playPause()
        case .jumpBack: jump(by: -1)
        case .jumpForward: jump(by: 1)
        case .stepPrevCue: stepCue(.previous)
        case .stepNextCue: stepCue(.next)
        case .go: go()
        case .rateUp, .rateDown, .rateReset:
            if let change = Self.rateChange(for: action) { rate(change) }
        }
    }

    func playPause() { engine.toggle() }

    func jump(by seconds: TimeInterval) {
        let target = max(0, engine.currentTime + seconds)   // mirrors DocumentView.jump
        seekTaskBox.task?.cancel()
        seekTaskBox.task = Task { await engine.seek(to: target) }
    }

    func stepCue(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction, typeID: context.showGoTypeID)
        else { return }
        seekTaskBox.task?.cancel()
        seekTaskBox.task = Task { await engine.seek(to: target.time) }
    }

    func go() {
        guard let item = document.model.activeItem,
              case .seekAndPlay(let time) = item.showGoDecision(from: engine.currentTime, typeID: context.showGoTypeID)
        else { return }
        seekTaskBox.task?.cancel()
        seekTaskBox.task = Task { await engine.seek(to: time); engine.play() }
    }

    func rate(_ change: PlaybackRateShortcuts.Change) {
        PlaybackRateController.apply(change, engine: engine, ltcEnabled: ltcEnabled)
    }

    nonisolated static func rateChange(for action: MiniPlaybackAction) -> PlaybackRateShortcuts.Change? {
        switch action {
        case .rateUp: return .up
        case .rateDown: return .down
        case .rateReset: return .reset
        default: return nil
        }
    }
}

/// Reference box so a cancellable seek task survives across the struct's copies
/// (host view rebuilds a fresh `MiniPlaybackActions` each render).
@MainActor
final class SeekTaskBox {
    var task: Task<Void, Never>?
}
