import SwiftUI

/// View modifier that owns the per-document `MIDIInput`, connects it to the
/// device chosen in Settings → MIDI, and applies each incoming message's bound
/// action to the document's `PlayerEngine` / `CueCommands`. Mirrors
/// `OSCServerHost` — same split (thin transport, pure decisions) and the same
/// reason for living outside `DocumentView` (SwiftLint's `type_body_length`).
///
/// Multiple open documents: each gets its own `MIDIInput` connected to the same
/// source, and CoreMIDI delivers to every connected port — so with two windows
/// open, both would respond. Like OSC (ADR-016), MIDI control implies a
/// single-document show-calling workflow.
struct MIDIInputHost: ViewModifier {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    var undoManager: UndoManager?
    /// Current editor mode, so cue creation stays forbidden in read-only Show
    /// mode while transport + cue navigation stay live (mirrors #592 for OSC).
    var editorMode: EditorMode
    /// The resolved Show-mode GO/step cue-type filter (#657): nil = All cues.
    var showGoTypeID: CuePointType.ID?

    // Observed, not owned: both are process-wide singletons shared with the
    // Settings window, matching `LTCOutputHost` and `MIDISettingsView`.
    @ObservedObject private var mapStore = MIDIMapStore.shared
    @ObservedObject private var learnSession = MIDILearnSession.shared
    @State private var input = MIDIInput()
    @State private var seekTask: Task<Void, Never>?
    @State private var showMonitor = false
    /// Last seen CC value per control, so press-edge detection can tell a
    /// button's press from its release.
    @State private var previousCC: [MIDIControlID: UInt8] = [:]
    /// Monotonic timestamp of the last applied continuous value, plus the
    /// pending trailing re-fire, so a fader sweep is coalesced to frame cadence.
    @State private var lastContinuousFire: TimeInterval?
    @State private var continuousTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { syncInput() }
            .onChange(of: mapStore.selectedInputUID) { _, _ in syncInput() }
            // Rebind the handler so the closure re-snapshots the current editor
            // mode and cue-type filter, rather than the values at connect time
            // (the same reason `OSCServerHost` re-syncs on these).
            .onChange(of: editorMode) { _, _ in syncInput() }
            .onChange(of: showGoTypeID) { _, _ in syncInput() }
            .onDisappear {
                input.stop()
                seekTask?.cancel()
                continuousTask?.cancel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .midiMonitorRequested)) { _ in
                showMonitor = true
            }
            .sheet(isPresented: $showMonitor) {
                MIDIMonitorView(input: input)
            }
    }

    private func syncInput() {
        input.onMessage = { dispatch($0) }
        learnSession.onLearned = { control, action in
            MIDIMapStore.shared.learn(control, as: action)
        }
        input.start(inputUID: mapStore.selectedInputUID)
    }

    private func dispatch(_ message: MIDIMessage) {
        // Learn intercepts everything while armed, so binding a control never
        // also fires whatever it was previously bound to.
        if learnSession.isActive {
            learnSession.capture(message)
            rememberCC(message)
            return
        }
        guard let control = MIDIControlID(message: message),
              let action = mapStore.map.action(for: control)
        else {
            rememberCC(message)
            return
        }

        let value = MIDIDispatchGate.value(of: message)
        if action.isContinuous {
            fireContinuous(action, value: value)
        } else if MIDIDispatchGate.shouldFireDiscrete(message, previousCCValue: previousCC[control]) {
            apply(MIDICommandDispatcher.effect(for: action, value: value, engine: snapshot()))
        }
        rememberCC(message)
    }

    /// Applies a continuous target at most once per frame (spec: rapid fader CC
    /// is coalesced so a sweep doesn't overwhelm the seek path or, for LTC
    /// level, write `UserDefaults` on every message). Coalescing must not swallow
    /// the *end* of a sweep, so a suppressed message is re-fired when the window
    /// closes — the fader's resting position is what the user actually sees.
    private func fireContinuous(_ action: MIDIAction, value: UInt8) {
        continuousTask?.cancel()
        let now = ProcessInfo.processInfo.systemUptime
        guard !MIDIDispatchGate.shouldFireContinuous(now: now, lastFiredAt: lastContinuousFire) else {
            lastContinuousFire = now
            apply(MIDICommandDispatcher.effect(for: action, value: value, engine: snapshot()))
            return
        }
        let delay = MIDIDispatchGate.continuousDelay(now: now, lastFiredAt: lastContinuousFire)
        continuousTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            apply(MIDICommandDispatcher.effect(for: action, value: value, engine: snapshot()))
        }
    }

    private func rememberCC(_ message: MIDIMessage) {
        guard case let .controlChange(channel, number, value) = message else { return }
        previousCC[MIDIControlID(channel: channel, kind: .cc, number: number)] = value
    }

    private func snapshot() -> MIDIEngineSnapshot {
        MIDIEngineSnapshot(
            currentTime: engine.currentTime,
            duration: engine.duration,
            rateRange: PlayerEngine.playbackRateRange
        )
    }

    private func apply(_ effect: MIDIEffect?) {
        guard let effect else { return }
        switch effect {
        case .seek(let time):
            seek(to: time)
        case .setRate(let rate):
            engine.setPlaybackRate(rate)
        case .setLTCLevel(let level):
            LTCRoutingStore.shared.update(LTCRoutingStore.shared.settings.settingAmplitude(level))
        case .keymap(let action):
            applyKeymap(action)
        }
    }

    /// Routes a `KeymapAction` to the same primitives `OSCServerHost` uses.
    /// Transport, GO/Stop and cue navigation are wired; the remaining editing
    /// actions are deliberately inert over MIDI in v1 (spec — out of scope).
    private func applyKeymap(_ action: KeymapAction) {
        switch action {
        case .playPause:
            if engine.rate == 0 { engine.play() } else { engine.pause() }
        case .go:
            goNextCueAndPlay()
        case .stop:
            engine.pause()
            seek(to: 0)
        case .stepNextCue:
            step(.next)
        case .stepPrevCue:
            step(.previous)
        case .addCue:
            // Read-only Show mode forbids cue creation by any means (#592).
            guard CueCreationGate.allows(
                editorMode: editorMode,
                hasActiveItem: document.model.activeItem != nil
            ) else { break }
            CueCommands.addCueAtPlayhead(time: engine.currentTime, document: document, undoManager: undoManager)
        default:
            break   // other KeymapActions are not wired to MIDI in v1
        }
    }

    /// Show-mode GO (#645): seek to the next cue after the playhead and play.
    /// Seek *then* play in one task so playback doesn't briefly start at the
    /// old playhead before the async seek lands.
    private func goNextCueAndPlay() {
        guard let item = document.model.activeItem,
              case .seekAndPlay(let time) = item.showGoDecision(from: engine.currentTime, typeID: showGoTypeID)
        else { return }
        seekTask?.cancel()
        seekTask = Task {
            await engine.seek(to: time)
            engine.play()
        }
    }

    private func seek(to time: TimeInterval) {
        seekTask?.cancel()
        seekTask = Task { await engine.seek(to: time) }
    }

    private func step(_ direction: MediaItem.PlayheadStep) {
        guard let item = document.model.activeItem,
              let target = item.cue(steppingFrom: engine.currentTime, direction: direction, typeID: showGoTypeID)
        else { return }
        seek(to: target.time)
    }
}

extension View {
    func midiInputHost(
        engine: PlayerEngine,
        document: CueListDocument,
        undoManager: UndoManager?,
        editorMode: EditorMode,
        showGoTypeID: CuePointType.ID?
    ) -> some View {
        modifier(MIDIInputHost(
            engine: engine,
            document: document,
            undoManager: undoManager,
            editorMode: editorMode,
            showGoTypeID: showGoTypeID
        ))
    }
}
