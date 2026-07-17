# Show mode — GO (walk the cues) — design

**Date:** 2026-07-17
**Issue:** #645
**Status:** Approved (grilling)

## Goal

Give the show caller a **GO** action in Show mode that walks the cue list one cue
at a time. Because OnlyCue plays continuously, the existing LTC timecode output
keeps streaming while playing — no new output pipeline. GO = seek to the next cue
+ make sure we're playing.

## Decisions (locked with the user)

- **Operating model (B — continuous playback):** GO jumps to the next cue and
  ensures playback. Playing → stays playing after the jump; stopped → GO starts
  playback.
- **GO semantics (within the current clip, scope A):**
  - `target` = the next cue in the active item strictly after the playhead
    (reuses `MediaItem.cue(steppingFrom:direction:.next)`).
  - `target != nil` → seek to `target.time` **and** play.
  - `target == nil` (playhead past the clip's last cue, or the clip has no cues)
    → **no-op** (nothing moves, playback state unchanged).
  - Playhead before the first cue → GO jumps to the first cue + plays (the
    natural result of `cue(steppingFrom:.next)`).
- **Triggers (all three, this feature):**
  - **GO button** in the Show-mode transport area.
  - **Return/Enter** keyboard shortcut, active **only in Show mode**; the space
    bar is untouched (stays play/pause). (Confirm Return isn't already bound in
    Show mode.)
  - **OSC `/onlycue/cue/go`** — new address, seek-next-cue + play. The existing
    `/onlycue/cue/next` keeps its meaning (seek only, playback state unchanged).
- **Show-mode scoping:** the GO **button** and **Return** shortcut appear/fire
  only when `editorMode == .show`; cue/lyric modes are unchanged. The OSC `go`
  command itself is not mode-gated (an external device fires it deliberately) —
  it always does seek-next-cue + play, sharing the same pure decision.
- **Timecode/LTC:** reuse the existing `LTCAudioOutput`/`LTCOutputHost`. LTC is
  already bound to the "playing" state, so continuous walk-the-cues playback
  covers it. This feature adds no output interface and does not auto-configure
  routing (the user still enables LTC + picks a channel in Settings).

## Architecture

Pure-core + thin-impure-boundary, matching the OSC layer (`OSCCommand.from` pure,
dispatch impure).

### Pure decision (`OnlyCue/Document/`)

`MediaItem.showGoDecision(from:)` — pure, unit-tested:

```swift
extension MediaItem {
    enum GoDecision: Equatable { case seekAndPlay(TimeInterval); case noOp }
    func showGoDecision(from currentTime: TimeInterval) -> GoDecision {
        guard let next = cue(steppingFrom: currentTime, direction: .next) else { return .noOp }
        return .seekAndPlay(next.time)
    }
}
```

### Wiring (thin, run-verified)

- **A shared `performGo`** on `DocumentView`: `switch activeItem.showGoDecision(from:
  engine.currentTime)` → `.seekAndPlay(t)` seeks then `engine.play()`; `.noOp`
  returns.
- **Button:** `TransportControls` gains an `onGo: (() -> Void)?` (nil in
  cue/lyric); a GO button renders only when non-nil (Show mode passes it).
- **Return shortcut:** a `ShowGoShortcut` host (like `PlayheadStepShortcuts`)
  bound to `.return`, `isEnabled: editorMode == .show && hasActiveItem`.
- **OSC:** add `case cueGo` to `OSCCommand` + `/onlycue/cue/go` in
  `supportedAddresses` and `from(_:)`; dispatch runs the same `performGo` path
  (seek next cue + `engine.play()`).

## Testing

- **Unit (`MediaItem.showGoDecision`):** next cue exists → `.seekAndPlay(nextTime)`;
  playhead past last cue → `.noOp`; empty cues → `.noOp`; playhead before first
  cue → `.seekAndPlay(firstTime)`; cue exactly at playhead is skipped (strict).
- **Unit (`OSCCommand`):** `/onlycue/cue/go` maps to `.cueGo`; appears in
  `supportedAddresses`.
- **Not unit-tested:** `engine.seek`/`play`, the button, the Return host —
  verified by running the app (Show mode, press GO / Return / send OSC).

## Hard-rules check

No `ProjectModel` schema change (GO is behaviour, not model — not routed through
`CueCommands`). No App Sandbox (ADR-007). No embedded media. macOS 14.0 floor
untouched. No version bump.

## Out of scope (future)

Cross-clip cue walking; a dedicated show-calling prompter screen; MTC / OSC-send
/ other timecode output interfaces.
</content>
