# Spec — Read LTC timecode from imported audio

**Status:** approved (grilled 2026-07-29, "LGTM")
**Area:** `area:ltc`, `area:media`
**Implements:** `docs/architecture.md` (LTC subsystem), ADR-019 (framerate vocabulary)

## Goal

When a designer imports a file that carries SMPTE LTC — either striped onto one
channel of a delivery mix, or a dedicated LTC-only audio file — OnlyCue reads
that timecode and shows it in the transport bar, clearly marked as coming from
the file rather than from OnlyCue's own clock.

## The surprise this spec addresses

**The decoder already exists and already works.** `LTCDecoder`,
`LTCAudioReader`, `StripedTimecodeTrack` and `StripedTimecodeHost` are all
shipped and unit-tested, and `TransportControls` already prefers the file's
striped timecode over the computed one. The feature is invisible for three
reasons, and this spec is about removing those three obstacles — not about
building a decoder.

1. **The readout is gated on the LTC *output* master switch.**
   `TransportControls.swift:161` wraps the SMPTE readout in
   `if ltcRoutingStore.settings.isEnabled`, which defaults to `false`. A user who
   only wants to *read* timecode has no reason to enable LTC *generation*, so the
   readout they need is hidden behind a switch for an unrelated feature.
2. **Only the down-mixed mono sum is decoded.** `AudioSampleReader` collapses
   every channel to mono. A stereo delivery with programme audio on L and LTC on
   R sums music on top of the biphase-mark square wave, and the decoder — which
   works from zero crossings — fails on the mush. Exactly the common case.
3. **Only the first 10 seconds are scanned.** `LTCAudioReader.decodeTimecodes`
   defaults to `maxSeconds: 10`. Files with a pre-roll, a countdown, or leading
   silence before the timecode starts read as "no LTC".

A fourth, smaller problem: `StripedTimecodeHost` re-decodes on every
`.task(id: item?.id)`, so switching back and forth between two clips re-reads and
re-decodes audio each time, including for files that have no LTC at all.

## Scope

### In

1. **Per-channel decode with auto-detection.** Read each audio channel
   separately and decode each until one yields LTC frames. First channel that
   decodes wins; the mono down-mix is no longer the only thing tried.
2. **Progressive scan.** Try the first 10 s; if nothing decodes, widen to 60 s
   before giving up. Cheap for the common case, tolerant of pre-roll.
3. **Decouple display from LTC output.** The SMPTE readout appears whenever
   there is something meaningful to show, independent of
   `LTCRoutingStore.settings.isEnabled`.
4. **Mark the source.** When the displayed timecode was decoded from the file,
   the readout is prefixed `FILE` instead of `SMPTE`, so a designer can tell at a
   glance whether they are looking at the file's own timecode or OnlyCue's
   computed one.
5. **Cache the result in memory, including negatives.** A "this file has no LTC"
   answer is as expensive to compute as a positive one and must not be recomputed
   on every clip switch.

### Out

- **Any change to LTC output.** Generation, routing, level and the master switch
  behave exactly as they do today. This is read-and-display only.
- **`.cuelist` schema change.** The decoded timecode is derived from the media
  file, not authored data — nothing is persisted, so `schemaVersion` is untouched.
- **`Timecode` / `SMPTEFramerate` / ADR-019.** No true 29.97 or 23.976. The
  decoder maps what it finds onto the existing four rates.
- **A badge in the media list.** The transport-bar prefix is the only affordance.
- **Slaving playback to incoming LTC.** Reading timecode off a file is not
  chasing timecode from a device; that is a separate feature.

## Accepted tradeoff — drift on 29.97 material

`StripedTimecodeTrack.timecode(atPlaybackSeconds:)` anchors on one decoded frame
and extrapolates linearly at the **nominal** framerate. On 29.97 fps material
labelled as 30, that accumulates roughly **3.6 seconds of error per hour**. Near
the anchor it is imperceptible; an hour into a long-form show it is not.

This is accepted as shipped behavior for this change, on the explicit
understanding that the fix is cheap and additive when it is wanted: measure the
effective rate empirically from two widely separated decoded frames
(`(frameCountB - frameCountA) / (secondsB - secondsA)`) and extrapolate at the
measured rate instead of the nominal one. That requires no change to `Timecode`
and no new case in `SMPTEFramerate`, so ADR-019 is not in the way.

## Behavior

### Given a stereo file with programme audio on L and LTC on R

```gherkin
Scenario: LTC on a single channel of a delivery mix
  Given a stereo media file whose right channel carries SMPTE LTC
  When the designer imports it and makes it the active clip
  Then the transport bar shows the decoded timecode prefixed "FILE"
  And the value tracks the playhead as it moves
```

### Given a dedicated LTC-only file

```gherkin
Scenario: A pure LTC audio file
  Given a mono media file that is nothing but LTC
  When it becomes the active clip
  Then the transport bar shows the decoded timecode prefixed "FILE"
```

### Given LTC that starts after a pre-roll

```gherkin
Scenario: Timecode begins after leading silence
  Given a file whose LTC starts 20 seconds in
  When it becomes the active clip
  Then the first 10-second scan finds nothing
  And the widened 60-second scan decodes the timecode
  And the transport bar shows it prefixed "FILE"
```

### Given a file with no timecode at all

```gherkin
Scenario: Ordinary music file
  Given a media file with no LTC on any channel
  When it becomes the active clip
  Then the transport bar shows OnlyCue's computed timecode prefixed "SMPTE"
  And switching away and back does not decode the file a second time
```

### Given the LTC output switch is off

```gherkin
Scenario: Reading does not depend on generating
  Given LTC output is disabled in Settings
  When a file carrying LTC becomes the active clip
  Then the transport bar still shows the decoded timecode
  And no LTC is generated or sent
```

## Acceptance criteria

- [ ] A stereo file with LTC on one channel only decodes; the mono sum alone
      would not have.
- [ ] A file whose LTC starts after 10 s but within 60 s decodes.
- [ ] The readout renders with `LTCRoutingStore.settings.isEnabled == false`.
- [ ] File-sourced timecode is prefixed `FILE`; computed timecode keeps `SMPTE`.
- [ ] Decoding a given file — positive **or** negative — happens at most once per
      run; re-selecting the clip is served from the cache.
- [ ] No `.cuelist` schema change; no new `SMPTEFramerate` case; no change to any
      LTC output path.
- [ ] Hardware-verified by the user against a real multichannel delivery file.
      Synthetic round-trip tests prove the decoder, not that real files decode.

## Notes for implementation

- `AudioSampleReader.readMonoSamples` is shared with the tempo analyzer — extend
  it with a channel selection rather than changing its default behavior.
- The channel count comes from the track's format description
  (`AudioStreamBasicDescription.mChannelsPerFrame`).
- The cache is keyed by something stable per media file and holds an
  `Optional<StripedTimecodeTrack>` so a miss and a known-negative are
  distinguishable. It is in-memory only, discarded on quit.
