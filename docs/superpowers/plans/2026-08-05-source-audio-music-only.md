# Implementation plan — source-audio "Music only" (#715)

REQUIRED SUB-SKILL: superpowers:subagent-driven-development
Spec: docs/superpowers/specs/2026-08-05-source-audio-music-only.md
Branch: issues/715 (off dev). BASE: edb4f42.

## Global constraints
- Hard rule: schema change ⇒ bump `ProjectModel.currentSchemaVersion` + add a migration (missing key → default). No sandbox entitlements. No `ProjectModel` mutation outside `Commands/`.
- Do NOT touch or rename the existing `MediaItem.ltcMuted` (that is LTC *output* mute) — the new control is a distinct concept.
- Conventional Commits, lowercase after prefix, no `Co-Authored-By`.
- TDD: failing test first. Unit tests don't need the UI runner; UI tests may hit the known automation-mode wedge (note + defer, never fake a pass).
- Detected LTC channel index is captured in-session but NOT persisted; only the per-clip user preference persists.

## Task 1 (A): capture the detected LTC channel index

`LTCAudioReader.detectTimecodes` finds the winning channel but discards it (`LTCAudioReader.swift:68` returns only `[DecodedFrame]`). Surface it.

- Modify `OnlyCue/LTC/LTCAudioReader.swift`: change the return so the winning channel index travels with the frames (e.g. a small `struct DetectionResult { let channel: Int; let frames: [DecodedFrame] }`, or return `(channel: Int, frames: [DecodedFrame])?`). `[]`/no-LTC → nil/empty with no channel.
- Thread the channel into `StripedTimecodeTrack` (add `let ltcChannel: Int`) where `MediaImporter.stripedTimecode` constructs it (`MediaImporter.swift:~153`), and through `StripedTimecodeCache`.
- Test (`OnlyCueTests`): with a synthesized/multi-channel fixture (reuse existing LTC test fixtures/helpers), assert detection reports the correct channel index; assert a no-LTC input reports none. Follow the existing `LTCAudioReaderTests` patterns.
- Update every call site of `detectTimecodes` for the new return shape (keep behavior identical for callers that only need the timecode).

## Task 2 (B): schema v19 — per-clip source-audio playback preference

- `OnlyCue/App/MediaItem.swift`: add one persisted field for the per-clip preference. Recommended: `var playsOriginalSourceAudio: Bool = false` — `false` = music-only (LTC channel muted, the default); `true` = play the original file including the timecode tone. Name must NOT collide with `ltcMuted`. Document the field.
- Bump `ProjectModel.currentSchemaVersion` 18 → 19. Add `MigrationV19` (v18→v19) mirroring `MigrationV17`/`MigrationV18` structure: a structurally no-op decode (missing key → `false`). Wire it into `ProjectModel+Migration.swift`'s decode switch.
- Update `docs/data-model.md`: correct the stale `schemaVersion: 15` to the real lineage through **v19**, and add the missing `ma2PushTarget` (v17) + this new field rows to the `MediaItem` table.
- Tests (`OnlyCueTests`): (a) round-trip a `MediaItem` with the new field; (b) a v18 document (missing the key) decodes to `false` (the migration test), following existing `Migration*Tests` patterns.

## Task 3 (C): channel-aware, music-only waveform peaks

`WaveformGenerator` forces `AVNumberOfChannelsKey: 1` (hard mono downmix, `WaveformGenerator.swift:~62`). Add a path that excludes the LTC channel.

- Add an optional "exclude channel" (or "music channels") parameter to the peak-generation path: read N channels (as `AudioSampleReader.readInterleavedSamples` does), sum only the non-LTC channels into the RMS buckets. When no channel is excluded, behavior is byte-identical to today (guard the new path).
- Extend `WaveformCache` key to include the channel selection so a music-only render and a full render don't collide.
- Wire `PreviewPane`/`WaveformContainer` to pass the detected LTC channel (from Task 1's cache) so the drawn waveform excludes it.
- Tests (`OnlyCueTests`): with a 2-channel fixture (music vs a loud/known channel), assert the excluded-channel peaks differ from the all-channel peaks and match the music-only channel; assert the no-exclusion path equals the current output (regression guard). Follow `WaveformGeneratorTests`/`WaveformCacheTests` patterns.

## Task 4 (D): mute the LTC channel on the AVPlayer path — SKETCH (hard, defer detail)

Reuse the existing `ProgramAudioTap` (`MTAudioProcessingTap`) from `LTCOutputHost`/`LTCAudioOutput`: when a clip is music-only and LTC is detected, install a tap on the `AVPlayerItem` audio mix that zeroes the LTC channel's samples and centers the surviving music channel to both ears. Toggle per `playsOriginalSourceAudio`. Flesh out into full steps when this task is reached.

## Task 5 (E): LTC-output path interaction — SKETCH

When LTC *output* is active, program audio already reroutes through `LTCAudioOutput`'s `AVAudioEngine`. Apply the same music-only source muting there so the two features compose. Flesh out when reached.

## Task 6 (F): UI — per-clip toggle + LTC badge

- Per-clip control "Source audio: Music only / Original (with timecode)" in `MediaEditSheet` and/or the `ItemListPane` context menu, routed through an undoable `CueCommands` mutation (like `setLTCMuted`). Distinct wording from the existing "Mute LTC for this clip".
- An LTC badge (icon + detected start timecode) on the clip row / waveform corner, shown only when LTC is detected.
- UITests mirror the Gherkin (deferred if the runner is wedged).

## Task 7 (G): wire-through + acceptance

End-to-end: import LTC file → auto music-only playback + music-only waveform + badge; toggle to original; persistence across reopen; no-LTC file unaffected. Acceptance UITests per the spec's Gherkin.

## Acceptance → task map
- Auto-mute timecode channel → 1,4,(5),7
- Revert to original + persists → 2,6,7
- Music-only waveform + badge → 1,3,6
- No LTC → inert → 1,3,4,7
