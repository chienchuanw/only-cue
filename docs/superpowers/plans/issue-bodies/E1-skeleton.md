## Spec source
Build-sequence step 1 — `docs/build-sequence.md` ("Skeleton")
Architecture — `docs/architecture.md#folder-layout`
Data model — `docs/data-model.md`

## Done when
Xcode project compiles. `DocumentGroup` opens an empty document. `.cuelist` UTType registered in `Info.plist`. `ProjectModel` Codable round-trip test passes.

## Leaves (expand JIT when MVP becomes active)
- [ ] Leaf: Define `ProjectModel`, `Cue`, `MediaReference`, `MediaKind` Codable types
- [ ] Leaf: `ProjectModelTests.test_jsonRoundTrip_preservesAllFields`
- [ ] Leaf: Register UTType `com.onlycue.cuelist` (Info.plist + UTExportedTypeDeclarations)
- [ ] Leaf: `CueListDocument` conforming to `ReferenceFileDocument`
- [ ] Leaf: `OnlyCueApp` with `DocumentGroup` opens an empty new doc

## Acceptance (epic-level Gherkin)
```gherkin
Scenario: New document opens
  Given the app is launched fresh
  When the user creates a new document
  Then a window appears titled "Untitled"
  And the cue list is empty
  And the preview pane shows the empty-state message

Scenario: ProjectModel round-trips through JSON
  Given a ProjectModel with media reference and 3 cues
  When the model is encoded to JSON and decoded back
  Then the decoded model equals the original
```

## Out of scope
- Player engine (E2)
- Media import (E3)
- Any UI beyond an empty document window
