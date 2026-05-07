## Spec source
Build-sequence step 4 — `docs/build-sequence.md` ("Video preview pane")
Architecture — `docs/architecture.md` (PreviewPane, PlayerEngine binding)

## Done when
`AVPlayerLayer` wrapped via `NSViewRepresentable`. `.mp4` and `.mov` show picture; transport drives video.

## Leaves
- [ ] Leaf: `AVPlayerLayerView: NSViewRepresentable` wrapping `AVPlayerLayer`
- [ ] Leaf: `PreviewPane` switches between video view and (placeholder for now) audio view based on `MediaReference.kind`
- [ ] Leaf: Aspect-fit sizing; preserves aspect ratio across window resizes
- [ ] Leaf: Visual smoke test — load `clip.mp4`, press play, confirm picture renders

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Video imports show picture
  Given a document with clip.mp4 imported
  Then the PreviewPane shows the first video frame
  When play() is called via TransportBar
  Then the video plays in sync with audio

Scenario: Audio imports show audio placeholder
  Given a document with sample.mp3 imported
  Then the PreviewPane shows an audio placeholder (waveform comes in E5)
```

## Out of scope
- Waveform rendering for audio (E5)
- Cue marker overlay (E8)
- Full-screen video
