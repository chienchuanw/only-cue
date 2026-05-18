# Edit Media Modal Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the "Edit Media" sheet a hero media preview (waveform for audio, a new poster frame for video) plus a read-only file-identity row, without changing the three editable fields or their commit flow.

**Architecture:** A new video poster-frame subsystem mirrors the existing waveform stack (`Generator` + `Cache` + view). A pure `MediaPreviewPlan` decides waveform vs poster vs unavailable from `MediaKind` + bookmark, keeping the decision unit-testable. `MediaEditSheet` gains a stacked layout: title → `MediaPreviewStrip` → identity row → existing `Form` → existing footer. `ItemListPane` passes the extra data explicitly (no `CueListDocument` handed to the modal).

**Tech Stack:** Swift 5.10, SwiftUI, AVFoundation (`AVAssetImageGenerator`), AppKit (`NSBitmapImageRep` for PNG), XCTest. macOS 14 deployment target.

**Spec:** `docs/superpowers/specs/2026-05-17-edit-media-modal-design.md`

**Conventions:**
- Conventional Commits, lowercase after prefix, imperative. No `Co-Authored-By` trailers.
- New source files under `OnlyCue/` and `OnlyCueTests/` are picked up by `project.yml` folder globbing — no `project.yml` edit needed, but `xcodegen generate` must be re-run before building (Task 6).
- Test command (whole suite):
  ```bash
  xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests 2>&1 | tail -30
  ```
  Single test class: append `-only-testing:OnlyCueTests/ClassName`.

---

## File Structure

- `OnlyCue/Media/VideoPosterGenerator.swift` — pure capture-time math + `AVAssetImageGenerator` wrapper.
- `OnlyCue/Media/VideoPosterCache.swift` — PNG disk cache, mirrors `WaveformCache`.
- `OnlyCue/UI/MediaPreviewPlan.swift` — pure enum: waveform / poster / unavailable.
- `OnlyCue/UI/MediaPreviewStrip.swift` — host view + `WaveformPreview` + `VideoPosterView` subviews.
- `OnlyCue/UI/MediaEditSheet.swift` — modify: add hero strip + identity row.
- `OnlyCue/UI/ItemListPane.swift` — modify: pass new params at the call site.
- `OnlyCueTests/VideoFixture.swift` — test helper: synthesize a short solid-color `.mov`.
- `OnlyCueTests/VideoPosterGeneratorTests.swift`, `OnlyCueTests/VideoPosterCacheTests.swift`, `OnlyCueTests/MediaPreviewPlanTests.swift` — new unit tests.
- `OnlyCueUITests/MediaEditSheetUITests.swift` — modify: assert identity + preview strip exist.

---

### Task 1: VideoFixture test helper

A synthesized short H.264 `.mov` is needed by the poster-generator tests (there is no committed media fixture; `SilentAudioFixture` is the established pattern for audio).

**Files:**
- Create: `OnlyCueTests/VideoFixture.swift`

- [ ] **Step 1: Write the helper**

```swift
import AVFoundation
import CoreImage
import XCTest

/// Synthesizes a short solid-color H.264 .mov in the temp directory.
/// Mirrors `SilentAudioFixture` for video poster-frame tests.
enum VideoFixture {

    /// Returns a file URL to a `duration`-second, `size` solid red .mov.
    static func makeMOV(
        duration: TimeInterval,
        size: CGSize = CGSize(width: 160, height: 120),
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let frameCount = max(Int(duration * Double(fps)), 1)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool, file: file, line: line)

        for frame in 0..<frameCount {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            let buffer = try XCTUnwrap(pixelBuffer, file: file, line: line)
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                // 32ARGB solid red: A=255, R=255, G=0, B=0
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                let count = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
                for i in stride(from: 0, to: count, by: 4) {
                    bytes[i] = 255; bytes[i + 1] = 255; bytes[i + 2] = 0; bytes[i + 3] = 0
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw try XCTUnwrap(writer.error, file: file, line: line)
        }
        return url
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add OnlyCueTests/VideoFixture.swift
git commit -m "test(media): add VideoFixture helper for poster-frame tests"
```

---

### Task 2: VideoPosterGenerator

**Files:**
- Create: `OnlyCue/Media/VideoPosterGenerator.swift`
- Test: `OnlyCueTests/VideoPosterGeneratorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import AVFoundation
import XCTest
@testable import OnlyCue

final class VideoPosterGeneratorTests: XCTestCase {

    func test_captureTime_isTenPercentOfDuration() {
        let t = VideoPosterGenerator.captureTime(forDurationSeconds: 100)
        XCTAssertEqual(CMTimeGetSeconds(t), 10, accuracy: 0.001)
    }

    func test_captureTime_negativeDuration_clampsToZero() {
        let t = VideoPosterGenerator.captureTime(forDurationSeconds: -5)
        XCTAssertEqual(CMTimeGetSeconds(t), 0, accuracy: 0.001)
    }

    func test_captureTime_subSecondClip_isNonNegative() {
        let t = VideoPosterGenerator.captureTime(forDurationSeconds: 0.5)
        XCTAssertGreaterThanOrEqual(CMTimeGetSeconds(t), 0)
        XCTAssertEqual(CMTimeGetSeconds(t), 0.05, accuracy: 0.001)
    }

    func test_poster_solidRedClip_returnsImageWithPositiveDimensions() async throws {
        let url = try await VideoFixture.makeMOV(duration: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try await VideoPosterGenerator.poster(for: AVURLAsset(url: url))

        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func test_poster_assetWithNoVideoTrack_throwsGenerationFailed() async {
        let composition = AVMutableComposition()
        do {
            _ = try await VideoPosterGenerator.poster(for: composition)
            XCTFail("Expected VideoPosterError.generationFailed")
        } catch {
            XCTAssertEqual(error as? VideoPosterError, .generationFailed)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/VideoPosterGeneratorTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'VideoPosterGenerator' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import AVFoundation
import CoreGraphics

enum VideoPosterError: Error, Equatable {
    case generationFailed
}

enum VideoPosterGenerator {

    /// Poster capture point: 10% into the clip (skips likely-black lead-in),
    /// clamped to ≥ 0 so sub-second / zero / negative durations are safe.
    static func captureTime(forDurationSeconds seconds: Double) -> CMTime {
        let clamped = max(seconds, 0) * 0.1
        return CMTime(seconds: clamped, preferredTimescale: 600)
    }

    /// Decodes a single representative frame. `maxPixelSize` caps the larger
    /// edge so cached posters stay small. Throws `.generationFailed` on any
    /// AVFoundation error (no video track, undecodable, etc.).
    static func poster(for asset: AVAsset, maxPixelSize: CGFloat = 512) async throws -> CGImage {
        let seconds: Double
        if let duration = try? await asset.load(.duration) {
            seconds = CMTimeGetSeconds(duration)
        } else {
            seconds = 0
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        do {
            let (image, _) = try await generator.image(at: captureTime(forDurationSeconds: seconds))
            return image
        } catch {
            throw VideoPosterError.generationFailed
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/VideoPosterGeneratorTests 2>&1 | tail -20`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Media/VideoPosterGenerator.swift OnlyCueTests/VideoPosterGeneratorTests.swift
git commit -m "feat(media): add video poster-frame generator"
```

---

### Task 3: VideoPosterCache

**Files:**
- Create: `OnlyCue/Media/VideoPosterCache.swift`
- Test: `OnlyCueTests/VideoPosterCacheTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import CoreGraphics
import XCTest
@testable import OnlyCue

final class VideoPosterCacheTests: XCTestCase {

    private func makeImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func makeIsolatedCache() -> VideoPosterCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("poster-cache-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return VideoPosterCache(directory: directory)
    }

    func test_writeThenRead_roundTripsImageDimensions() throws {
        let cache = makeIsolatedCache()
        try cache.write(makeImage(width: 64, height: 48), assetHash: "abc", maxPixelSize: 512)

        let recovered = cache.read(assetHash: "abc", maxPixelSize: 512)

        XCTAssertEqual(recovered?.width, 64)
        XCTAssertEqual(recovered?.height, 48)
    }

    func test_read_missingEntry_returnsNil() {
        XCTAssertNil(makeIsolatedCache().read(assetHash: "nope", maxPixelSize: 512))
    }

    func test_read_sizeMismatch_returnsNil() throws {
        let cache = makeIsolatedCache()
        try cache.write(makeImage(width: 10, height: 10), assetHash: "h1", maxPixelSize: 256)

        XCTAssertNil(cache.read(assetHash: "h1", maxPixelSize: 512))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/VideoPosterCacheTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'VideoPosterCache' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import AppKit
import CoreGraphics
import Foundation

/// PNG disk cache for video poster frames. Mirrors `WaveformCache`: keyed by
/// source-file SHA256 (reuse `WaveformCache.fileHash`) plus the max pixel size.
struct VideoPosterCache {

    let directory: URL

    static let shared: VideoPosterCache = {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return Self(directory: base.appendingPathComponent("OnlyCue/posters", isDirectory: true))
    }()

    func read(assetHash: String, maxPixelSize: Int) -> CGImage? {
        let url = entryURL(assetHash: assetHash, maxPixelSize: maxPixelSize)
        guard let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }

    func write(_ image: CGImage, assetHash: String, maxPixelSize: Int) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: entryURL(assetHash: assetHash, maxPixelSize: maxPixelSize), options: .atomic)
    }

    private func entryURL(assetHash: String, maxPixelSize: Int) -> URL {
        directory.appendingPathComponent("\(assetHash)-\(maxPixelSize).png")
    }
}
```

Note: `test_read_sizeMismatch_returnsNil` passes because the entry filename embeds `maxPixelSize`; a different size maps to a different (missing) file.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/VideoPosterCacheTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/Media/VideoPosterCache.swift OnlyCueTests/VideoPosterCacheTests.swift
git commit -m "feat(media): add video poster PNG disk cache"
```

---

### Task 4: MediaPreviewPlan (pure decision)

**Files:**
- Create: `OnlyCue/UI/MediaPreviewPlan.swift`
- Test: `OnlyCueTests/MediaPreviewPlanTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import OnlyCue

final class MediaPreviewPlanTests: XCTestCase {

    private func validBookmark() throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        try Data("x".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try Bookmarks.create(for: url)
    }

    func test_audio_validBookmark_isWaveform() throws {
        let plan = MediaPreviewPlan.make(kind: .audio, bookmarkData: try validBookmark())
        guard case .waveform = plan else { return XCTFail("expected .waveform, got \(plan)") }
    }

    func test_video_validBookmark_isPoster() throws {
        let plan = MediaPreviewPlan.make(kind: .video, bookmarkData: try validBookmark())
        guard case .poster = plan else { return XCTFail("expected .poster, got \(plan)") }
    }

    func test_garbageBookmark_isUnavailable() {
        let plan = MediaPreviewPlan.make(kind: .audio, bookmarkData: Data([0x00]))
        XCTAssertEqual(plan, .unavailable)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MediaPreviewPlanTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'MediaPreviewPlan' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Pure decision for what the Edit Media preview strip should show. Resolving
/// the bookmark here keeps the choice (and the stale/missing → fallback rule)
/// unit-testable. Security-scoped file *access* happens later, in the subviews'
/// async loaders.
enum MediaPreviewPlan: Equatable {
    case waveform(URL)
    case poster(URL)
    case unavailable

    static func make(kind: MediaKind, bookmarkData: Data) -> MediaPreviewPlan {
        guard let resolved = try? Bookmarks.resolve(bookmarkData), !resolved.isStale else {
            return .unavailable
        }
        switch kind {
        case .audio: return .waveform(resolved.url)
        case .video: return .poster(resolved.url)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/MediaPreviewPlanTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/MediaPreviewPlan.swift OnlyCueTests/MediaPreviewPlanTests.swift
git commit -m "feat(ui): add MediaPreviewPlan preview-source decision"
```

---

### Task 5: MediaPreviewStrip view (waveform + poster subviews)

SwiftUI views are exercised at the UI-test level (Task 7); their decision/IO seams are already unit-covered by Tasks 2–4. This task wires them into one host view.

**Files:**
- Create: `OnlyCue/UI/MediaPreviewStrip.swift`

- [ ] **Step 1: Write the view**

```swift
import AVFoundation
import SwiftUI

/// Hero preview for the Edit Media sheet. Audio → reused `WaveformView`;
/// video → `VideoPosterGenerator` frame; stale/missing/failed → kind-icon
/// fallback. Fixed height, full width, neutral background.
struct MediaPreviewStrip: View {

    let kind: MediaKind
    let bookmarkData: Data
    var height: CGFloat = 72

    private static let waveformResolution = 1_200
    private static let posterMaxPixelSize: CGFloat = 512

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipped()
            .accessibilityIdentifier("mediaEditPreviewStrip")
    }

    @ViewBuilder
    private var content: some View {
        switch MediaPreviewPlan.make(kind: kind, bookmarkData: bookmarkData) {
        case .waveform(let url):
            WaveformPreview(url: url, resolution: Self.waveformResolution, fallback: fallback)
        case .poster(let url):
            VideoPosterPreview(url: url, maxPixelSize: Self.posterMaxPixelSize, fallback: fallback)
        case .unavailable:
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: kind == .audio ? "waveform" : "film")
            .font(.system(size: 28))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Loads (cache → generate → cache) and renders an audio waveform at a
/// modal-sized resolution. Reuses `WaveformCache`/`WaveformGenerator`.
private struct WaveformPreview<Fallback: View>: View {
    let url: URL
    let resolution: Int
    let fallback: Fallback

    @State private var peaks: [Float]?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                fallback
            } else if let peaks {
                WaveformView(peaks: peaks)
                    .padding(.vertical, 6)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let hash = try? WaveformCache.fileHash(url) else { failed = true; return }
        if let cached = WaveformCache.shared.read(assetHash: hash, resolution: resolution) {
            peaks = cached
            return
        }
        do {
            let generated = try await WaveformGenerator.peaks(
                for: AVURLAsset(url: url), resolution: resolution
            )
            try? WaveformCache.shared.write(generated, assetHash: hash, resolution: resolution)
            peaks = generated
        } catch {
            failed = true
        }
    }
}

/// Loads (cache → generate → cache) and renders a video poster frame.
private struct VideoPosterPreview<Fallback: View>: View {
    let url: URL
    let maxPixelSize: CGFloat
    let fallback: Fallback

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                fallback
            } else if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let hash = try? WaveformCache.fileHash(url) else { failed = true; return }
        let sizeKey = Int(maxPixelSize)
        if let cached = VideoPosterCache.shared.read(assetHash: hash, maxPixelSize: sizeKey) {
            image = cached
            return
        }
        do {
            let generated = try await VideoPosterGenerator.poster(
                for: AVURLAsset(url: url), maxPixelSize: maxPixelSize
            )
            try? VideoPosterCache.shared.write(generated, assetHash: hash, maxPixelSize: sizeKey)
            image = generated
        } catch {
            failed = true
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -15`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/MediaPreviewStrip.swift
git commit -m "feat(ui): add MediaPreviewStrip hero preview view"
```

---

### Task 6: Restructure MediaEditSheet + wire ItemListPane

**Files:**
- Modify: `OnlyCue/UI/MediaEditSheet.swift`
- Modify: `OnlyCue/UI/ItemListPane.swift:26-45`

- [ ] **Step 1: Replace the body of `MediaEditSheet`**

Replace the entire `var body` computed property (lines 22–62) with the version below. Everything else in the file (`item`, `framerate`, callbacks, `@State`, `syncDraftsFromItem`, `commit`) is unchanged. The `LabeledContent`/`Toggle` blocks keep their existing accessibility identifiers verbatim.

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Media")
                .font(.headline)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            MediaPreviewStrip(
                kind: item.media.kind,
                bookmarkData: item.media.bookmarkData
            )

            HStack(spacing: 8) {
                Image(systemName: item.media.kind == .audio ? "waveform" : "film")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.media.displayName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.media.kind == .audio ? "Audio" : "Video") · "
                         + TimeFormat.smpte(item.media.duration, rate: framerate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .accessibilityIdentifier("mediaEditIdentity")

            Divider()

            Form {
                LabeledContent("Name") {
                    TextField(item.media.displayName, text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("mediaEditNameField")
                }
                LabeledContent("Start timecode") {
                    TextField("HH:MM:SS:FF", text: $tcDraft)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(tcInvalid ? Color.red : Color.clear, lineWidth: 1)
                        )
                        .onChange(of: tcDraft) { _, _ in tcInvalid = false }
                        .accessibilityIdentifier("mediaEditStartTimecodeField")
                }
                Toggle("Mute LTC for this clip", isOn: $mutedDraft)
                    .accessibilityIdentifier("mediaEditMuteToggle")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("mediaEditCancel")
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mediaEditSave")
            }
            .padding(20)
        }
        .frame(width: 460)
        .onAppear { syncDraftsFromItem() }
    }
```

- [ ] **Step 2: Verify the ItemListPane call site needs no change**

Open `OnlyCue/UI/ItemListPane.swift:26-45`. The `MediaEditSheet(item:framerate:onSave:onCancel:)` initializer signature is unchanged (the new data is read from `item.media` inside the sheet), so **no edit is required here**. Confirm by reading the call site — if it still compiles against the unchanged initializer, leave it as-is. This step is a verification, not an edit.

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild build -scheme OnlyCue -destination 'platform=macOS' 2>&1 | tail -15`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run the existing media-edit unit tests (regression)**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/CueCommandsUpdateMediaItemTests 2>&1 | tail -15`
Expected: PASS (5 tests) — commit flow untouched.

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/UI/MediaEditSheet.swift
git commit -m "feat(ui): give Edit Media sheet a hero preview and identity row"
```

---

### Task 7: Extend MediaEditSheet UI test

**Files:**
- Modify: `OnlyCueUITests/MediaEditSheetUITests.swift`

- [ ] **Step 1: Add a new UI test method**

Insert this method after `test_cancelDiscardsEdits()` (after line 67), before the `openEditSheet` helper:

```swift
    func test_editSheet_showsIdentityAndPreviewStrip() throws {
        let app = launchWithSeed(.threeCuesAt1And3And6)
        defer { app.terminate() }

        try openEditSheet(in: app)

        let nameField = app.textFields["mediaEditNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Sheet should open.")

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "mediaEditPreviewStrip").firstMatch.exists,
            "Hero preview strip should be present in the Edit Media sheet."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "mediaEditIdentity").firstMatch.exists,
            "File-identity row should be present in the Edit Media sheet."
        )
    }
```

- [ ] **Step 2: Run the UI test**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/MediaEditSheetUITests 2>&1 | tail -25`
Expected: PASS, or `XCTSkip` on the CI right-click path (same tolerated flakiness documented in the file header). The two pre-existing tests must still PASS/skip — not fail.

- [ ] **Step 3: Commit**

```bash
git add OnlyCueUITests/MediaEditSheetUITests.swift
git commit -m "test(ui): assert Edit Media sheet shows identity and preview strip"
```

---

### Task 8: Full suite + regenerate

**Files:** none (verification + project regen)

- [ ] **Step 1: Regenerate the Xcode project (new source folders/files)**

Run: `xcodegen generate`
Expected: `Created project at .../OnlyCue.xcodeproj`.

- [ ] **Step 2: Run the full unit suite**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests 2>&1 | tail -30`
Expected: all OnlyCueTests pass, including the four new test classes and the unchanged `CueCommandsUpdateMediaItemTests`.

- [ ] **Step 3: Run SwiftLint (pre-build script parity)**

Run: `swiftlint 2>&1 | tail -10`
Expected: no new violations in the added files (warnings-as-errors is Release-only, but keep it clean).

- [ ] **Step 4: Final commit if anything regenerated/changed**

```bash
git status --porcelain
# Only if project metadata or lint autofix changed tracked files:
git add -A && git commit -m "chore: regenerate project after edit-media modal redesign"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task |
|---|---|
| Layout (hero stacked, ~460pt, identity row, unchanged Form/footer, unchanged a11y IDs) | Task 6 |
| Hero preview: audio→WaveformView, video→poster, placeholder, fallback on stale/fail | Task 5 |
| Identity row (kind icon + filename + `Kind · SMPTE duration`) | Task 6 |
| `VideoPosterGenerator` (10% capture, clamp, tolerance .zero, appliesPreferredTrackTransform) | Task 2 |
| `VideoPosterCache` (SHA256+size key, PNG, posters/ dir) | Task 3 |
| `MediaPreviewStrip` switches on `item.media.kind` | Task 5 |
| Explicit params from ItemListPane, no `CueListDocument` to modal | Task 6 (reads `item.media`; initializer unchanged → no document passed) |
| No `CueCommands`/`MediaItemEdit`/undo/schema change | Verified in Task 6 Step 4 |
| Tests: VideoPosterGeneratorTests / VideoPosterCacheTests / MediaPreview decision / extend UI test | Tasks 2, 3, 4, 7 |

`MediaPreviewStripTests` from the spec is realized as **`MediaPreviewPlanTests`** (Task 4): the spec's three cases (audio→waveform, video→poster, stale→fallback) map to the pure `MediaPreviewPlan`, which is the unit-testable seam. The SwiftUI strip itself is covered by the UI test in Task 7. This is a deliberate, equivalent realization of the spec's testing intent.

**2. Placeholder scan:** No TBD/TODO; every code step is complete and compilable.

**3. Type consistency:** `VideoPosterError.generationFailed` (Task 2) is asserted in Task 2 tests only. `VideoPosterGenerator.poster(for:maxPixelSize:)` / `captureTime(forDurationSeconds:)` signatures consistent across Tasks 2 and 5. `VideoPosterCache.read/write(assetHash:maxPixelSize:)` consistent across Tasks 3 and 5. `MediaPreviewPlan.make(kind:bookmarkData:)` consistent across Tasks 4 and 5. `MediaPreviewStrip(kind:bookmarkData:)` consistent across Tasks 5 and 6. `WaveformCache.fileHash` and `WaveformGenerator.peaks(for:resolution:)` reused with their real existing signatures. Accessibility identifiers (`mediaEdit*`) preserved verbatim from the current file.
