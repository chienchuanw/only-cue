## Spec source
Build-sequence step 3 — `docs/build-sequence.md` ("Media import")
Data model — `docs/data-model.md` (`MediaReference`, bookmark behavior)

## Done when
`⌘O` and drag-drop accept supported audio + video. Bookmark created and stored in `MediaReference`. Player loads the imported asset.

## Leaves
- [ ] Leaf: `Bookmarks.swift` — create/resolve security-scoped bookmarks, `staleness` handling
- [ ] Leaf: `BookmarksTests` — round-trip create → encode → decode → resolve on a temp file
- [ ] Leaf: File importer (`fileImporter` modifier) accepting `.audio` + `.movie` content types
- [ ] Leaf: Drag-drop onto `DocumentView` accepts the same types
- [ ] Leaf: Reject unsupported file types with an inline alert
- [ ] Leaf: On import success, populate `ProjectModel.media` and call `PlayerEngine.load(asset:)`

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: Import audio via file picker
  Given a new document is open
  When the user picks sample.mp3 via ⌘O
  Then ProjectModel.media is populated
  And the player loads the asset within 250ms
  And subsequent save round-trips include the bookmark

Scenario: Import video via drag-drop
  Given a new document is open
  When the user drops clip.mp4 onto the window
  Then ProjectModel.media.kind == .video
  And the preview pane is video (per E4)

Scenario: Reject unsupported file
  Given a new document is open
  When the user drops doc.pdf onto the window
  Then an alert appears explaining only audio/video are supported
  And ProjectModel.media remains nil
```

## Out of scope
- Re-link UX for missing media (E9)
- Multi-media-per-document (out of MVP per data-model.md)
