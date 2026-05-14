# UI test seed mechanism — design

Date: 2026-05-14
Status: Approved (autonomous)
Issue: #261

## Goal

Make the three `XCTSkip`-scaffolded scenarios in `OnlyCueUITests/CueGroupDragUITests.swift` runnable, by giving UI tests a way to launch the app into a document with known cues and a populated `loadedDuration` — without any production-code change.

## Approach: Option A (pure)

UI tests construct a seed `.cuelist` JSON in Swift, write it to a temp file, and launch the app passing the path as a command-line argument. macOS's `NSApplication` automatically routes file-path arguments through `application(_:openURLs:)`, which SwiftUI's `DocumentGroup` handles by opening the document. No `#if DEBUG` code added to the app.

For the `MediaReference`, the seed JSON points at a 30-second silent stereo `.m4a` bundled in `OnlyCueUITests/Resources/`. Bookmarks are created in-process at test time from that bundle URL. The app is not sandboxed (ADR-007), so the bookmark resolves cleanly in the launched app process and `AVPlayer` populates `loadedDuration` from real metadata.

## Components

### Bundled fixture

`OnlyCueUITests/Resources/silent-30s.m4a` — 30 seconds of stereo silence at 44.1 kHz AAC. Generated once via:

```
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 30 -c:a aac -b:a 64k silent-30s.m4a
```

Resulting file size is ~10–20 KB. Committed to git as a binary asset. `project.yml`'s `OnlyCueUITests` target adds `Resources/silent-30s.m4a` as a bundle resource.

### Seed builder (Swift, test target)

`OnlyCueUITests/Support/SeedDocumentBuilder.swift` — pure helper that:

1. Resolves the bundled silent audio URL via `Bundle(for:).url(forResource:withExtension:)`.
2. Creates a `MediaReference` with `displayName = "silent-30s.m4a"`, `kind = .audio`, `duration = 30`, `bookmarkData = Bookmarks.create(for:)`.
3. Builds a `ProjectModel` with `schemaVersion = 11`, one `MediaItem` containing the cues for the named seed, and `activeItemID` set.
4. Encodes to pretty-printed JSON with `JSONEncoder` (matching `CueListDocument.fileWrapper(...)`).
5. Writes to a unique temp path (`FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).cuelist")`).
6. Returns the path as `String` for `XCUIApplication.launchArguments`.

To avoid duplicating production types in tests, the seed builder uses `@testable import OnlyCue` so it can construct `ProjectModel`, `MediaItem`, `MediaReference`, and `Cue` directly. (`Bookmarks`, `ProjectModel`, etc. are `internal`.)

### Seed catalog

Three named seeds, each a static factory on the builder:

| Seed name | Cues (time, bpm) | Initial selection |
|---|---|---|
| `threeCues_1_3_6` | (1.0, nil), (3.0, nil), (6.0, nil) | none |
| `threeCues_1_3_6_select_first_two` | same as above | cues at 1.0 and 3.0 |
| `threeCues_1_3_6_with_120bpm_tempo` | (0.0, 120), (1.0, nil), (3.0, nil), (6.0, nil) | none |

Selection is conveyed by an out-of-band file the UI test reads after launch — but simpler: the UI test selects cues via the UI itself after the document opens, so the seed catalog stores cue-time arrays only. The "select first two" variant is implemented by the test code calling out to ⌘-click the first two rows after launch, not by the seed.

This simplifies to two distinct seed JSON shapes:
- `threeCues_1_3_6` (no BPM)
- `threeCues_1_3_6_with_120bpm_tempo` (BPM cue at 0)

### UI test scenarios

`OnlyCueUITests/CueGroupDragUITests.swift` — remove `XCTSkip` from all three tests. Each test:

1. Calls `SeedDocumentBuilder.write(.threeCues_1_3_6)` (or the tempo variant) → gets a path.
2. Sets `app.launchArguments = [seedPath]` and calls `app.launch()`.
3. Waits for the `cueMarkersOverlay` to appear (`waitForExistence(timeout: 10)`).
4. Drives the scenario (select cues via cue list, drag markers, etc.).
5. Asserts via cue-row accessibility labels.

## Out of scope

- Seed catalog inside the app (rejected: Option B was the runner-up; keeping seed shapes in test code avoids polluting the production entry point).
- Fake AVPlayer injection (rejected: behavioral drift risk).
- Generalizing to a fixture system for non-waveform UI tests — keep the seed builder scoped to what these three tests need.

## Risk and fallback

If `XCUIApplication.launchArguments = [path]` does NOT trigger automatic document open in CI (e.g., macOS Sequoia changes, or App Translocation moves the binary), fall back to:

- Add a `#if DEBUG` block in `OnlyCueApp.swift` that scans `CommandLine.arguments` for a `.cuelist` path and calls `NSDocumentController.shared.openDocument(withContentsOf:display:completionHandler:)` explicitly.

This fallback is a single ~10-line addition; not implementing it preemptively to keep the production diff zero.

## Acceptance criteria

- [ ] `silent-30s.m4a` bundled in `OnlyCueUITests/Resources/` and listed in `project.yml`.
- [ ] `SeedDocumentBuilder` writes a valid v11 `.cuelist` that the production loader decodes without migration.
- [ ] `test_groupDrag_shiftsAllSelectedCuesRigidly` passes.
- [ ] `test_dragUnselectedMarker_replacesSelectionAndMovesSolo` passes.
- [ ] `test_shiftDrag_snapsAnchorToNearestBeat` passes.
- [ ] No production-code file is modified.
- [ ] CI green; existing UI tests unchanged.
