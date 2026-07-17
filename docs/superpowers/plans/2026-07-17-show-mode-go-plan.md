# Show mode GO — implementation plan

**Spec:** `docs/superpowers/specs/2026-07-17-show-mode-go-design.md`
**Issue:** #645

Small feature, mostly reuse. Pure-core TDD; triggers run-verified.

## Phase 1 — pure decision + OSC command (TDD)

1. **Red:** `OnlyCueTests/MediaItemShowGoTests.swift` — `showGoDecision(from:)`:
   next-cue → `.seekAndPlay(nextTime)`; past-last → `.noOp`; empty → `.noOp`;
   before-first → `.seekAndPlay(firstTime)`; cue at exact playhead skipped.
   Plus `OSCCommandTests`: `/onlycue/cue/go` → `.cueGo`, present in
   `supportedAddresses`.
2. **Green:**
   - `MediaItem.GoDecision` + `showGoDecision(from:)` (reuses
     `cue(steppingFrom:.next)`).
   - `OSCCommand.cueGo` + address in `supportedAddresses` + `from(_:)`.

## Phase 2 — wiring (thin; run-verified)

3. `DocumentView.performGo()`: `switch activeItem?.showGoDecision(from:
   engine.currentTime)` → `.seekAndPlay(t)` → seek then `engine.play()`.
4. `TransportControls` gains `onGo: (() -> Void)?`; GO button renders only when
   non-nil. `DocumentView` passes `onGo: { performGo() }` only in Show mode
   (nil otherwise).
5. `ShowGoShortcut` host bound to `.return`, `isEnabled: editorMode == .show &&
   hasActiveItem`, added to the `.background` ZStack. Verify `.return` isn't
   already bound.
6. `OSCServerHost.dispatch`: `case .cueGo` → run the same seek-next-cue + play.

## Phase 3 — verify + PR

7. Full unit suite + SwiftLint green.
8. Run the app: Show mode → GO button, Return, and an OSC `/onlycue/cue/go`
   message each jump to the next cue and play; no-op at the last cue; cue/lyric
   modes show no GO button and Return does nothing.
9. PR (feat), self-review, CI green, merge.

## Out of scope

Cross-clip walking; prompter screen; MTC/OSC-send.
</content>
