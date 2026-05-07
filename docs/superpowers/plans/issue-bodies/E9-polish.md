## Spec source
Build-sequence step 9 — `docs/build-sequence.md` ("Polish")
Data model — `docs/data-model.md` (bookmark stale handling)
Verification — `docs/verification.md`

## Done when
Empty states. Missing-media relink alert. App icon. Default keyboard shortcuts wired. About box. Standard macOS feel.

## Leaves
- [ ] Leaf: Empty document state ("Drop a file or press ⌘O")
- [ ] Leaf: Bookmark-stale alert with "Relink media…" button on document open
- [ ] Leaf: Replace `Untitled` window title with `<filename> — OnlyCue` once saved
- [ ] Leaf: Standard shortcuts wired: ⌘N, ⌘O, ⌘S, ⌘Z, ⌘⇧Z, Space (play/pause), M (add cue), ⌫ (delete cue), ←/→ (jump 1s)
- [ ] Leaf: App icon (1024px → all required sizes via `iconutil`)
- [ ] Leaf: About box with version and credits
- [ ] Leaf: First-launch nudge with link to docs (one-time, dismissible)

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Missing media on reopen
  Given Show.cuelist references sample.mp3
  And sample.mp3 has been moved to a new folder
  When the user opens Show.cuelist
  Then an alert appears with "Relink media…"
  And the cue list is still rendered (cues survive missing media)
  When the user clicks "Relink media…" and picks the new path
  Then the bookmark is updated, document is silently re-saved
  And playback works
```

## Out of scope
- Auto-update / Sparkle (post-MVP)
- Settings/preferences UI (post-MVP)
- Theme / accent customization
