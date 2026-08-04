# Source-audio "Music only" — mute the detected LTC channel + music-only waveform

**Status:** drafted 2026-08-05 (grilled), pending approval
**Builds on:** the v0.19.0 LTC-from-imported-audio scan (#712 / #713)

## Goal

When an imported audio file has LTC (linear timecode) striped on a **dedicated** channel, the user should — by default — **hear only the music** (the LTC channel is auto-muted) and **see a waveform of only the music**, with a small badge signalling that LTC was detected. A per-clip switch reverts to playing the original raw file for verification.

## Hard assumption

LTC always lives on **its own channel**, separate from the music — which is what the per-channel decoder already implies (it decodes each channel independently and picks the one that reads as clean timecode). LTC mixed into the same channel as music is **out of scope** (it can't be decoded, let alone separated).

## Confirmed decisions (from grilling 2026-08-05)

1. **Channel layout** — primary case is a stereo file: one channel music (mono), one channel LTC. The model stores an *arbitrary* detected channel index, so a "stereo music + separate LTC channel" file works later without a redesign.
2. **Playback** — auto-mute the detected LTC channel by default → music only. The surviving music channel(s) are **downmixed to center** (both ears). A **per-clip toggle** switches that clip to "Original (with timecode)" for verification.
3. **Waveform** — draw **music-only peaks** (exclude the LTC channel). Add a small **LTC badge** (icon + the detected start timecode) so "this file has striped LTC" is still visible, without spending waveform height on an unreadable buzz.
4. **Persistence** — the per-clip playback-mode preference is written into the `.cuelist` document (**schema v18 → v19 + migration**). The detected channel *index* is **not** persisted — it is re-scanned per session (so a future detection improvement isn't bound by stale data).
5. **Naming** — do **not** call it "LTC mute": that name is taken by `MediaItem.ltcMuted`, which mutes the LTC **output** OnlyCue generates. This new control is about the **source/imported** audio. Frame it per-clip as a source-audio mode: **"Music only" / "Original (with timecode)"**.

## Data model

- **`MediaItem`** gains a per-clip source-audio playback mode (default resolves to *music-only* when LTC is detected). **Schema v19 + migration** (missing key → default; Hard Rule per `docs/data-model.md`).
- **Detection must surface the winning channel index.** Today `LTCAudioReader.detectTimecodes` discards it (`LTCAudioReader.swift:68`); capture it into the in-memory `StripedTimecodeTrack` / `StripedTimecodeCache` so playback and the waveform can act on it.

## Acceptance criteria (Gherkin)

```gherkin
Scenario: Auto-mute the timecode channel
  Given an imported stereo file with music on one channel and LTC on the other
  When the clip is played
  Then only the music is heard (the LTC channel is silent)
  And the music is heard centered in both ears

Scenario: Revert to the original audio
  Given a clip whose LTC channel is auto-muted
  When the user switches that clip's source-audio mode to "Original (with timecode)"
  Then the whole file plays, including the LTC tone
  And the choice is remembered after closing and reopening the project

Scenario: Music-only waveform
  Given an imported file with a detected LTC channel
  Then the waveform shows only the music channel's peaks (no LTC buzz)
  And a badge shows the detected LTC start timecode

Scenario: No LTC present
  Given an imported file with no LTC on any channel
  Then playback and the waveform are unchanged (the feature does not intervene)
```

## Out of scope (v1)

- LTC mixed into the same channel as the music.
- Manual channel override (hand-picking which channel is LTC) — the "Original (with timecode)" toggle is the escape hatch if detection is wrong.
- Any change to the LTC **output** feature or the existing `MediaItem.ltcMuted`.

## Technical approach & risks

- **Playback muting** — `AVPlayer` (the primary playback path, `PlayerEngine.swift`) cannot mute a single channel. Reuse the existing **`ProgramAudioTap` (`MTAudioProcessingTap`)** infrastructure from the LTC-output path (`LTCOutputHost` / `LTCAudioOutput`) to zero the LTC channel's samples and center the music. **Two playback paths** must be handled: plain `AVPlayer`, and the `AVAudioEngine` path already active when LTC **output** is on. This dual path is the main complexity.
- **Waveform** — `WaveformGenerator` currently forces `AVNumberOfChannelsKey: 1` (a hard mono downmix at generation, `WaveformGenerator.swift:62`). Add a channel-aware peak path (read N channels via the existing `AudioSampleReader.readInterleavedSamples` / `channel(_:of:in:)`, sum only non-LTC channels) and extend the `WaveformCache` key by the channel selection.
- **Schema** — v19 migration (Hard Rule: bump `ProjectModel.currentSchemaVersion`, add `MigrationV18`, update `docs/data-model.md` — which is currently stale at v15 and should be corrected to v18/v19).
```
