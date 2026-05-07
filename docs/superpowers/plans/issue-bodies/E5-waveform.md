## Spec source
Build-sequence step 5 — `docs/build-sequence.md` ("Waveform")
Architecture — `docs/architecture.md` (Media/, WaveformGenerator, WaveformCache)

## Done when
`WaveformGenerator` produces peak arrays asynchronously. `WaveformView` renders peaks via `Canvas`. Peak cache hits on second open of the same asset.

## Leaves
- [ ] Leaf: `WaveformGenerator` — `AVAssetReader` → `[Float]` peaks, async, cancellable
- [ ] Leaf: `WaveformGeneratorTests` — peak count == requested resolution, deterministic
- [ ] Leaf: `WaveformCache` — on-disk cache keyed by `(assetSHA, resolution)`
- [ ] Leaf: `WaveformView` — `Canvas` renderer, mono, no zoom for v1
- [ ] Leaf: Wire `WaveformView` into `PreviewPane` for `.audio` assets
- [ ] Leaf: Performance — 5-min audio renders in < 1s on cache miss; instant on hit

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Waveform appears for imported audio
  Given the user has just imported sample.mp3
  Then a waveform is rendered in the preview pane within 1 second
  And the waveform width spans the full preview area

Scenario: Peak cache hits on reopen
  Given a document was previously saved with sample.mp3
  When the document is reopened
  Then the waveform appears within 250ms (no regeneration)
```

## Out of scope
- Cue markers on waveform (E8)
- Zoom / horizontal scroll
- Stereo / multi-channel display
