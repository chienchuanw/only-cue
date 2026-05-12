# LTC master switch + exclusive audio routing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a master on/off switch for LTC output (default off), and when LTC is on, route the media's program audio through the LTC `AVAudioEngine` onto the Track L/R channels with `AVPlayer` muted, so the LTC signal never sums with program audio at the device.

**Architecture:** `LTCRoutingSettings` gains `isEnabled`. When the LTC engine runs, an `MTAudioProcessingTap` on the `AVPlayerItem` siphons program PCM, an `AVAudioConverter` reshapes it to the engine render format, a lock-protected `ProgramAudioRingBuffer` buffers it, and a second `AVAudioPlayerNode` in `LTCAudioOutput` plays it onto the `trackLeft`/`trackRight` channels. `AVPlayer.volume` is set to 0 while this is active. `AVPlayer` stays the master clock.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioConverter`, `MTAudioProcessingTap`, `AVMutableAudioMix`), XCTest. macOS 14+. No App Sandbox (ADR-007).

**Spec:** `docs/superpowers/specs/2026-05-13-ltc-master-switch-exclusive-audio-design.md`

**Commit/branch conventions** (`CLAUDE.md`): Conventional Commits, lowercase after prefix, imperative, **no `Co-Authored-By` trailers**. Run `swiftlint` clean before each commit. Tests run via the Xcode scheme: `xcodegen generate` if `project.yml`/structure changed, then `xcodebuild test -scheme OnlyCue -destination 'platform=macOS'` (or run the target test in Xcode). New `.swift` files under `OnlyCue/LTC/` and `OnlyCueTests/` are picked up by the existing folder rules in `project.yml` — re-run `xcodegen generate` after creating them so the `.xcodeproj` sees them.

---

## File structure

| File | Responsibility | New? |
|---|---|---|
| `OnlyCue/LTC/LTCRoutingSettings.swift` | Add `isEnabled: Bool` (default false), tolerant `Codable`, update `isComplete`. | modify |
| `OnlyCue/UI/AudioSettingsView.swift` | "Enable LTC output" toggle; channel table + warnings only when enabled; hint when enabled with no track channels. | modify |
| `OnlyCue/LTC/ProgramAudioRingBuffer.swift` | Pure deinterleaved-float ring buffer: `push` / `drain` (zero-fill on underrun) / `flush`. Unit-tested. | **new** |
| `OnlyCue/LTC/ProgramAudioTap.swift` | `MTAudioProcessingTap` + `AVMutableAudioMix` wrapper; converts tapped audio to render format and pushes to a `ProgramAudioRingBuffer`. | **new** |
| `OnlyCue/LTC/LTCAudioOutput.swift` | Generalize `makeBuffer` to multi-channel; add `programNode` + program buffer pump; thread `programTap` through `start` / `stop` / `update` / `restartEngine`. | modify |
| `OnlyCue/Media/PlayerEngine.swift` | `setAudioMuted(_:)` helper. | modify |
| `OnlyCue/UI/LTCOutputHost.swift` | Gate on `isEnabled`; mute `AVPlayer` + attach `ProgramAudioTap` on engine start; restore + detach on stop; re-attach on `currentItem` change. | modify |
| `OnlyCueTests/LTCRoutingSettingsTests.swift` | `isEnabled` default, `isComplete`, Codable round-trip with/without key. | modify |
| `OnlyCueTests/LTCAudioOutputTests.swift` | Generalized `makeBuffer` cases. | modify |
| `OnlyCueTests/ProgramAudioRingBufferTests.swift` | Ring-buffer behavior. | **new** |
| `OnlyCueUITests/AudioSettingsUITests.swift` | Toggle shows/hides channel table + warning. | **new** (or add to existing settings UITest file if one exists — check `OnlyCueUITests/`) |
| `docs/architecture.md`, `docs/verification.md` | Document the master switch + exclusive-audio behavior and the manual verification steps. | modify |

---

## Task 1: `LTCRoutingSettings.isEnabled`

**Files:**
- Modify: `OnlyCue/LTC/LTCRoutingSettings.swift`
- Test: `OnlyCueTests/LTCRoutingSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `OnlyCueTests/LTCRoutingSettingsTests.swift`:

```swift
func test_default_isDisabled() {
    XCTAssertFalse(LTCRoutingSettings.default.isEnabled)
}

func test_isComplete_requiresEnabledAndLTCChannel() {
    let disabledWithLTC = LTCRoutingSettings(isEnabled: false, deviceUID: nil, channelRoles: [.ltc, .trackLeft])
    XCTAssertFalse(disabledWithLTC.isComplete)

    let enabledNoLTC = LTCRoutingSettings(isEnabled: true, deviceUID: nil, channelRoles: [.silent, .trackLeft])
    XCTAssertFalse(enabledNoLTC.isComplete)

    let enabledWithLTC = LTCRoutingSettings(isEnabled: true, deviceUID: nil, channelRoles: [.ltc, .trackLeft])
    XCTAssertTrue(enabledWithLTC.isComplete)
}

func test_codable_missingIsEnabledKey_decodesAsDisabled() throws {
    // Legacy payload written before `isEnabled` existed.
    let legacy = #"{"channelRoles":["ltc","trackLeft"]}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: legacy)
    XCTAssertFalse(decoded.isEnabled)
    XCTAssertEqual(decoded.channelRoles, [.ltc, .trackLeft])
    XCTAssertNil(decoded.deviceUID)
}

func test_codable_roundTrip_preservesIsEnabled() throws {
    let original = LTCRoutingSettings(isEnabled: true, deviceUID: "dev-1", channelRoles: [.ltc, .trackLeft, .trackRight])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(LTCRoutingSettings.self, from: data)
    XCTAssertEqual(decoded, original)
}
```

Also update any existing test that constructs `LTCRoutingSettings(deviceUID:channelRoles:)` — keep that initializer working (see Step 3) so existing tests compile unchanged. Existing tests that call `.assigning`, `.resized`, etc. need no change.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/LTCRoutingSettingsTests`
Expected: FAIL — `isEnabled` is not a member; `init(isEnabled:deviceUID:channelRoles:)` does not exist.

- [ ] **Step 3: Implement**

In `OnlyCue/LTC/LTCRoutingSettings.swift`, change the struct:

```swift
struct LTCRoutingSettings: Codable, Equatable, Sendable {

    /// Master switch for LTC output. When `false` the LTC engine never runs and
    /// the routing's channel assignments are dormant. Default `false` — a fresh
    /// install emits no timecode until the user opts in.
    var isEnabled: Bool

    /// Core Audio device UID of the selected output, or `nil` to follow the
    /// system default output device.
    var deviceUID: String?

    /// Role per output channel, indexed 0-based.
    var channelRoles: [ChannelRole]

    static let `default` = Self(isEnabled: false, deviceUID: nil, channelRoles: [])

    init(isEnabled: Bool = false, deviceUID: String?, channelRoles: [ChannelRole]) {
        self.isEnabled = isEnabled
        self.deviceUID = deviceUID
        self.channelRoles = channelRoles
    }

    // MARK: Codable — tolerate payloads written before `isEnabled` existed.

    private enum CodingKeys: String, CodingKey { case isEnabled, deviceUID, channelRoles }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        deviceUID = try container.decodeIfPresent(String.self, forKey: .deviceUID)
        channelRoles = try container.decodeIfPresent([ChannelRole].self, forKey: .channelRoles) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(deviceUID, forKey: .deviceUID)
        try container.encode(channelRoles, forKey: .channelRoles)
    }
```

Update `isComplete`:

```swift
    /// Routing is usable once LTC is enabled and an LTC output channel is assigned.
    var isComplete: Bool { isEnabled && ltcChannel != nil }
```

Update the transform helpers so they carry `isEnabled` through (they currently rebuild `Self(deviceUID:channelRoles:)`):

```swift
    func assigning(_ role: ChannelRole, toChannel channel: Int) -> Self {
        guard channelRoles.indices.contains(channel) else { return self }
        var roles = channelRoles
        if role.isUnique {
            for index in roles.indices where roles[index] == role { roles[index] = .silent }
        }
        roles[channel] = role
        return Self(isEnabled: isEnabled, deviceUID: deviceUID, channelRoles: roles)
    }

    func selectingDevice(uid: String?) -> Self {
        Self(isEnabled: isEnabled, deviceUID: uid, channelRoles: channelRoles)
    }

    func resized(toChannelCount count: Int) -> Self {
        let clamped = max(0, count)
        var roles = channelRoles
        if roles.count > clamped {
            roles = Array(roles.prefix(clamped))
        } else if roles.count < clamped {
            roles.append(contentsOf: repeatElement(.silent, count: clamped - roles.count))
        }
        return Self(isEnabled: isEnabled, deviceUID: deviceUID, channelRoles: roles)
    }

    func withDefaultRoles(forChannelCount count: Int) -> Self {
        Self(isEnabled: isEnabled, deviceUID: deviceUID, channelRoles: Self.defaultRoles(forChannelCount: count))
    }

    /// Toggle the master switch.
    func settingEnabled(_ enabled: Bool) -> Self {
        Self(isEnabled: enabled, deviceUID: deviceUID, channelRoles: channelRoles)
    }

    /// The first channel carrying a `trackLeft` / `trackRight` role, if any.
    var trackLeftChannel: Int? { channel(for: .trackLeft) }
    var trackRightChannel: Int? { channel(for: .trackRight) }

    /// Whether any channel carries program (track) audio.
    var hasTrackChannels: Bool { trackLeftChannel != nil || trackRightChannel != nil }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/LTCRoutingSettingsTests`
Expected: PASS (all, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add OnlyCue/LTC/LTCRoutingSettings.swift OnlyCueTests/LTCRoutingSettingsTests.swift
git commit -m "feat(ltc): add isEnabled master switch to routing settings"
```

---

## Task 2: Audio settings — "Enable LTC output" toggle

**Files:**
- Modify: `OnlyCue/UI/AudioSettingsView.swift`
- Test: `OnlyCueUITests/AudioSettingsUITests.swift` (new; or extend an existing settings UITest)

- [ ] **Step 1: Write the failing UITest**

Create `OnlyCueUITests/AudioSettingsUITests.swift`:

```swift
import XCTest

final class AudioSettingsUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func test_enableToggle_revealsChannelTable() {
        let app = XCUIApplication()
        app.launch()
        // Open Settings → Audio. Adjust this navigation to match the app's
        // existing settings UITests (see how SettingsShortcutsUITests / the
        // keymap pane test opens the window).
        SettingsWindow.open(app, tab: "Audio")

        let toggle = app.switches["enableLTCOutputToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        // Default off → channel table hidden.
        XCTAssertFalse(app.popUpButtons["audioChannelRolePicker.0"].exists)

        toggle.click()
        XCTAssertTrue(app.popUpButtons["audioChannelRolePicker.0"].waitForExistence(timeout: 2))

        toggle.click()
        XCTAssertFalse(app.popUpButtons["audioChannelRolePicker.0"].exists)
    }
}
```

> If there is no existing helper for opening the Settings window in `OnlyCueUITests/`, replace `SettingsWindow.open(app, tab: "Audio")` with the same approach the existing settings UITests use (search `OnlyCueUITests/` for `Settings` / `Cmd+,`). Do not invent a helper that doesn't exist.

- [ ] **Step 2: Run the UITest to verify it fails**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/AudioSettingsUITests`
Expected: FAIL — no element with identifier `enableLTCOutputToggle`.

- [ ] **Step 3: Implement the toggle + conditional sections**

In `OnlyCue/UI/AudioSettingsView.swift`:

Add a binding next to `deviceSelection`:

```swift
    private var enabledSelection: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { store.update(settings.settingEnabled($0)) }
        )
    }
```

Restructure `body`'s `Form` so the device picker / channel table / warning live inside an `if settings.isEnabled` block, with the toggle always visible:

```swift
    var body: some View {
        Form {
            Section {
                Toggle("Enable LTC output", isOn: enabledSelection)
                    .accessibilityIdentifier("enableLTCOutputToggle")
            } footer: {
                Text("When on, OnlyCue generates SMPTE LTC and sends it — plus the media's audio on the Track channels — to the chosen output device. The media's normal audio output is muted while LTC is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.isEnabled {
                Section {
                    Picker("Output device", selection: deviceSelection) {
                        Text("System Default").tag(String?.none)
                        ForEach(devices) { device in
                            Text("\(device.name) — \(device.outputChannelCount) ch").tag(String?.some(device.uid))
                        }
                    }
                    .accessibilityIdentifier("audioOutputDevicePicker")

                    HStack {
                        Button("Refresh Devices") { refreshDevices() }
                        Spacer()
                        Button("Reset Routing") { resetRouting() }
                    }
                } footer: {
                    Text("The LTC generator plays onto the channel assigned “LTC”. A 4-channel interface can carry LTC on one channel and stereo track audio on two others.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Channel assignment") {
                    ForEach(0..<channelCount, id: \.self) { channel in
                        Picker("Channel \(channel + 1)", selection: roleSelection(forChannel: channel)) {
                            ForEach(ChannelRole.allCases, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .accessibilityIdentifier("audioChannelRolePicker.\(channel)")
                    }
                }

                if settings.ltcChannel == nil {
                    Section {
                        Label("No channel is assigned to LTC.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .accessibilityIdentifier("audioRoutingWarning")
                    }
                } else if !settings.hasTrackChannels {
                    Section {
                        Label("No channel is assigned to Track L / Track R — the media’s audio will be silent on this device while LTC is on.", systemImage: "speaker.slash.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .accessibilityIdentifier("audioNoTrackChannelsHint")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .accessibilityIdentifier("audioSettings")
        .onAppear {
            refreshDevices()
            reconcileChannelCount()
        }
    }
```

Note: `settings.isComplete` is no longer the warning condition (it now also requires `isEnabled`); use `settings.ltcChannel == nil` for the warning as shown. `reconcileChannelCount()` / `refreshDevices()` are still called on appear regardless of the toggle — harmless when disabled.

- [ ] **Step 4: Run the UITest to verify it passes**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueUITests/AudioSettingsUITests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add OnlyCue/UI/AudioSettingsView.swift OnlyCueUITests/AudioSettingsUITests.swift
git commit -m "feat(ltc): enable-LTC toggle in audio settings, gate channel table"
```

---

## Task 3: Generalize `LTCAudioOutput.makeBuffer` to multi-channel

**Files:**
- Modify: `OnlyCue/LTC/LTCAudioOutput.swift`
- Test: `OnlyCueTests/LTCAudioOutputTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `OnlyCueTests/LTCAudioOutputTests.swift`:

```swift
func test_makeBufferMulti_placesEachSourceOnItsChannel() throws {
    let left: [Float] = [0.1, 0.2, 0.3, 0.4]
    let right: [Float] = [-0.1, -0.2, -0.3, -0.4]
    let buffer = try XCTUnwrap(LTCAudioOutput.makeBuffer(
        channels: [(samples: left, channel: 1), (samples: right, channel: 2)],
        format: try format(channels: 4)))
    XCTAssertEqual(Int(buffer.frameLength), 4)
    let data = try XCTUnwrap(buffer.floatChannelData)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: data[0], count: 4)), [Float](repeating: 0, count: 4))
    XCTAssertEqual(Array(UnsafeBufferPointer(start: data[1], count: 4)), left)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: data[2], count: 4)), right)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: data[3], count: 4)), [Float](repeating: 0, count: 4))
}

func test_makeBufferMulti_clampsOutOfRangeChannel() throws {
    let mono: [Float] = [1, 2]
    let buffer = try XCTUnwrap(LTCAudioOutput.makeBuffer(
        channels: [(samples: mono, channel: 9)], format: try format(channels: 2)))
    let data = try XCTUnwrap(buffer.floatChannelData)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: data[1], count: 2)), mono)  // clamped to last
}

func test_makeBufferMulti_mismatchedLengths_isNil() throws {
    XCTAssertNil(LTCAudioOutput.makeBuffer(
        channels: [(samples: [1, 2, 3], channel: 0), (samples: [1, 2], channel: 1)],
        format: try format(channels: 2)))
}

func test_makeBufferMulti_empty_isNil() throws {
    XCTAssertNil(LTCAudioOutput.makeBuffer(channels: [], format: try format(channels: 2)))
    XCTAssertNil(LTCAudioOutput.makeBuffer(channels: [(samples: [], channel: 0)], format: try format(channels: 2)))
}
```

(Keep the existing `test_makeBuffer_*` tests — the single-channel wrapper stays.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/LTCAudioOutputTests`
Expected: FAIL — no `makeBuffer(channels:format:)` overload.

- [ ] **Step 3: Implement**

In `OnlyCue/LTC/LTCAudioOutput.swift`, add the multi-channel builder and make the existing one delegate:

```swift
    /// Build a multichannel float PCM buffer placing each `(samples, channel)`
    /// entry on its channel of `format` and silence everywhere else. Out-of-range
    /// channel indices clamp into bounds. All `samples` arrays must be the same
    /// (non-zero) length. Pure — exposed for tests.
    static func makeBuffer(channels: [(samples: [Float], channel: Int)], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let frameCount = channels.first?.samples.count, frameCount > 0,
              channels.allSatisfy({ $0.samples.count == frameCount }),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let dest = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channelCount = Int(format.channelCount)
        for index in 0..<channelCount { dest[index].update(repeating: 0, count: frameCount) }
        for (samples, channel) in channels {
            let target = min(max(0, channel), channelCount - 1)
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { dest[target].update(from: base, count: frameCount) }
            }
        }
        return buffer
    }

    /// Single mono-on-one-channel form — thin wrapper kept for the LTC pump and
    /// its existing tests.
    static func makeBuffer(monoSamples: [Float], format: AVAudioFormat, channel: Int) -> AVAudioPCMBuffer? {
        makeBuffer(channels: [(samples: monoSamples, channel: channel)], format: format)
    }
```

Delete the old multi-line body of `makeBuffer(monoSamples:format:channel:)` (replaced by the wrapper above).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/LTCAudioOutputTests`
Expected: PASS (new + existing).

- [ ] **Step 5: Commit**

```bash
git add OnlyCue/LTC/LTCAudioOutput.swift OnlyCueTests/LTCAudioOutputTests.swift
git commit -m "refactor(ltc): generalize makeBuffer to multiple source channels"
```

---

## Task 4: `ProgramAudioRingBuffer` (pure)

**Files:**
- Create: `OnlyCue/LTC/ProgramAudioRingBuffer.swift`
- Test: `OnlyCueTests/ProgramAudioRingBufferTests.swift`

Design: a fixed-capacity, single-producer/single-consumer FIFO of interleaved-by-frame stereo float samples, stored as one flat `[Float]` of `capacityFrames * 2` (L,R,L,R…). `push` drops the oldest frames if it would overflow (better to glitch old audio than block the realtime tap). `drain(frameCount:)` returns exactly `frameCount` stereo frames, zero-filling the tail on underrun. Guarded by an `os_unfair_lock` (cheap, safe to take briefly in the tap callback). Not `@MainActor` — touched from the realtime tap thread and the engine pump.

- [ ] **Step 1: Write the failing tests**

Create `OnlyCueTests/ProgramAudioRingBufferTests.swift`:

```swift
import XCTest
@testable import OnlyCue

final class ProgramAudioRingBufferTests: XCTestCase {

    func test_pushThenDrain_returnsFramesInOrder() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 8)
        ring.push(interleavedStereo: [1, 10, 2, 20, 3, 30])   // 3 frames
        let out = ring.drain(frameCount: 3)
        XCTAssertEqual(out, [1, 10, 2, 20, 3, 30])
    }

    func test_drain_moreThanAvailable_zeroFillsTail() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 8)
        ring.push(interleavedStereo: [1, 1, 2, 2])            // 2 frames
        let out = ring.drain(frameCount: 4)
        XCTAssertEqual(out, [1, 1, 2, 2, 0, 0, 0, 0])
    }

    func test_drain_emptyBuffer_isAllZeros() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        XCTAssertEqual(ring.drain(frameCount: 3), [Float](repeating: 0, count: 6))
    }

    func test_wrapAround_preservesOrder() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [1, 1, 2, 2, 3, 3])      // 3 frames
        _ = ring.drain(frameCount: 2)                         // consume frames 1,2 → tail at index 2
        ring.push(interleavedStereo: [4, 4, 5, 5])            // 2 more frames, wraps
        XCTAssertEqual(ring.drain(frameCount: 3), [3, 3, 4, 4, 5, 5])
    }

    func test_push_overCapacity_dropsOldestFrames() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 3)
        ring.push(interleavedStereo: [1, 1, 2, 2, 3, 3])      // fills exactly
        ring.push(interleavedStereo: [4, 4, 5, 5])            // overflows by 2 → drop frames 1,2
        // Remaining oldest→newest: 3, 4, 5
        XCTAssertEqual(ring.drain(frameCount: 3), [3, 3, 4, 4, 5, 5])
    }

    func test_flush_discardsEverything() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [1, 1, 2, 2])
        ring.flush()
        XCTAssertEqual(ring.drain(frameCount: 2), [0, 0, 0, 0])
    }

    func test_oddSampleCount_isIgnored() {
        // Defensive: a stray non-frame-aligned push must not corrupt the buffer.
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [1, 1, 2])  // 2.5 frames — rejected wholesale
        XCTAssertEqual(ring.drain(frameCount: 1), [0, 0])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/ProgramAudioRingBufferTests`
Expected: FAIL — `ProgramAudioRingBuffer` undefined.

- [ ] **Step 3: Implement**

Create `OnlyCue/LTC/ProgramAudioRingBuffer.swift`:

```swift
import Foundation
import os

/// Lock-protected single-producer / single-consumer FIFO of interleaved stereo
/// float samples (`L, R, L, R, …`), used to hand the media's program audio from
/// the realtime `MTAudioProcessingTap` callback to `LTCAudioOutput`'s buffer
/// pump. Fixed capacity in frames; overflowing `push` drops the oldest frames
/// (glitch the past, never block the tap), underrunning `drain` zero-fills the
/// tail. Frame = one (L, R) pair = 2 samples.
///
/// Not `@MainActor` — both ends run off the main actor. Pure logic — unit-tested.
final class ProgramAudioRingBuffer: @unchecked Sendable {

    private let capacityFrames: Int
    private var storage: [Float]          // capacityFrames * 2
    private var head = 0                  // next frame to read, in frames
    private var count = 0                 // frames currently buffered
    private var lock = os_unfair_lock()

    init(capacityFrames: Int) {
        let cap = max(1, capacityFrames)
        self.capacityFrames = cap
        self.storage = [Float](repeating: 0, count: cap * 2)
    }

    /// Append interleaved stereo samples. A non-even count is rejected wholesale.
    func push(interleavedStereo samples: [Float]) {
        guard !samples.isEmpty, samples.count % 2 == 0 else { return }
        let incomingFrames = samples.count / 2
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        // Source frame range to actually keep (last `capacityFrames` of them).
        let keepFrames = min(incomingFrames, capacityFrames)
        let srcFrameStart = incomingFrames - keepFrames

        // If keeping `keepFrames` would exceed capacity, drop that many oldest.
        let overflow = (count + keepFrames) - capacityFrames
        if overflow > 0 {
            head = (head + overflow) % capacityFrames
            count -= overflow
        }

        let writeStart = (head + count) % capacityFrames
        for i in 0..<keepFrames {
            let dstFrame = (writeStart + i) % capacityFrames
            let src = (srcFrameStart + i) * 2
            storage[dstFrame * 2] = samples[src]
            storage[dstFrame * 2 + 1] = samples[src + 1]
        }
        count += keepFrames
    }

    /// Return exactly `frameCount` interleaved stereo frames; zero-fills any tail
    /// not backed by buffered data.
    func drain(frameCount: Int) -> [Float] {
        guard frameCount > 0 else { return [] }
        var out = [Float](repeating: 0, count: frameCount * 2)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let take = min(frameCount, count)
        for i in 0..<take {
            let srcFrame = (head + i) % capacityFrames
            out[i * 2] = storage[srcFrame * 2]
            out[i * 2 + 1] = storage[srcFrame * 2 + 1]
        }
        head = (head + take) % capacityFrames
        count -= take
        return out
    }

    func flush() {
        os_unfair_lock_lock(&lock)
        head = 0
        count = 0
        os_unfair_lock_unlock(&lock)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/ProgramAudioRingBufferTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add OnlyCue/LTC/ProgramAudioRingBuffer.swift OnlyCueTests/ProgramAudioRingBufferTests.swift
git commit -m "feat(ltc): program-audio ring buffer for tapped media samples"
```

---

## Task 5: `ProgramAudioTap` — `MTAudioProcessingTap` wrapper

**Files:**
- Create: `OnlyCue/LTC/ProgramAudioTap.swift`

Not headless-testable (needs a live `AVPlayerItem` rendering audio) — verified manually. Keep the type small and dependency-light so it's obviously correct by reading.

Behavior: `attach(to item:, renderSampleRate:)` builds an `AVMutableAudioMix` with one `AVMutableAudioMixInputParameters` for the item's first audio track, creates an `MTAudioProcessingTap` (post-effects), assigns the mix to `item.audioMix`. In the tap's `prepare` callback it builds an `AVAudioConverter` from the processing format to a stereo, deinterleaved Float32 format at `renderSampleRate`. In `process` it pulls source frames, converts, and `push`es interleaved stereo into the `ProgramAudioRingBuffer`. `detach()` sets `item.audioMix = nil` and releases the tap. The ring buffer is owned by the caller (`LTCAudioOutput`) and passed in.

- [ ] **Step 1: Implement (no test — manual verification)**

Create `OnlyCue/LTC/ProgramAudioTap.swift`:

```swift
import AVFoundation
import MediaToolbox

/// Siphons an `AVPlayerItem`'s program audio via an `MTAudioProcessingTap`,
/// resamples it to a stereo Float32 stream at the LTC engine's render sample
/// rate, and pushes it into a `ProgramAudioRingBuffer` for `LTCAudioOutput` to
/// play onto the Track L / Track R channels. While a tap is attached the host
/// (`LTCOutputHost`) also mutes `AVPlayer` directly, so this is the *only* path
/// the program audio takes.
///
/// Not headless-testable — needs a live, rendering `AVPlayerItem`. Verified by
/// running the app. The realtime callbacks do only conversion + a brief locked
/// push (no allocation in steady state beyond the converter's output buffer,
/// which is sized once on `prepare`).
final class ProgramAudioTap {

    private let ring: ProgramAudioRingBuffer
    private let renderSampleRate: Double
    private weak var item: AVPlayerItem?
    private var tap: MTAudioProcessingTap?

    /// State shared with the C callbacks via the tap's `clientInfo` pointer.
    private final class Context {
        let ring: ProgramAudioRingBuffer
        let renderSampleRate: Double
        var converter: AVAudioConverter?
        var sourceFormat: AVAudioFormat?
        var outputFormat: AVAudioFormat?
        init(ring: ProgramAudioRingBuffer, renderSampleRate: Double) {
            self.ring = ring
            self.renderSampleRate = renderSampleRate
        }
    }
    private var context: Context?

    init(ring: ProgramAudioRingBuffer, renderSampleRate: Double) {
        self.ring = ring
        self.renderSampleRate = renderSampleRate
    }

    /// Install the tap onto `item`'s first audio track. No-op if the item has no
    /// audio track. Replaces any tap previously attached by this object.
    func attach(to item: AVPlayerItem) {
        detach()
        guard let track = item.asset.tracks(withMediaType: .audio).first else { return }

        let ctx = Context(ring: ring, renderSampleRate: renderSampleRate)
        let clientInfo = Unmanaged.passRetained(ctx).toOpaque()

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo            // hand the Context to later callbacks
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<Context>.fromOpaque(storage).release()
            },
            prepare: { tap, _, processingFormat in
                let ctx = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let asbd = processingFormat.pointee
                guard let source = AVAudioFormat(streamDescription: &asbd.pointee) else { return }
                // Hmm: `processingFormat` is `UnsafePointer<AudioStreamBasicDescription>`.
                ctx.sourceFormat = source
                let output = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                           sampleRate: ctx.renderSampleRate,
                                           channels: 2,
                                           interleaved: true)
                ctx.outputFormat = output
                if let output { ctx.converter = AVAudioConverter(from: source, to: output) }
            },
            unprepare: { tap in
                let ctx = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                ctx.converter = nil
                ctx.sourceFormat = nil
                ctx.outputFormat = nil
            },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                let ctx = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
                guard status == noErr,
                      let source = ctx.sourceFormat,
                      let output = ctx.outputFormat,
                      let converter = ctx.converter,
                      let inBuf = AVAudioPCMBuffer(pcmFormat: source, bufferListNoCopy: bufferListInOut)
                else { return }
                inBuf.frameLength = AVAudioFrameCount(numberFramesOut.pointee)
                let capacity = AVAudioFrameCount(Double(inBuf.frameLength) * output.sampleRate / source.sampleRate) + 16
                guard let outBuf = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
                var consumed = false
                let err: NSError? = {
                    var e: NSError?
                    converter.convert(to: outBuf, error: &e) { _, statusOut in
                        if consumed { statusOut.pointee = .noDataNow; return nil }
                        consumed = true
                        statusOut.pointee = .haveData
                        return inBuf
                    }
                    return e
                }()
                guard err == nil, outBuf.frameLength > 0, let ch = outBuf.floatChannelData?[0] else { return }
                let n = Int(outBuf.frameLength) * 2   // interleaved stereo
                ctx.ring.push(interleavedStereo: Array(UnsafeBufferPointer(start: ch, count: n)))
            }
        )

        var tapOut: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects, &tapOut)
        guard status == noErr, let createdTap = tapOut?.takeRetainedValue() else {
            Unmanaged<Context>.fromOpaque(clientInfo).release()
            return
        }
        self.tap = createdTap
        self.context = ctx
        self.item = item

        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = createdTap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }

    /// Remove the tap and stop touching the item.
    func detach() {
        item?.audioMix = nil
        item = nil
        tap = nil          // ARC releases; `finalize` releases the retained Context
        context = nil
        ring.flush()
    }

    deinit { detach() }
}
```

> **Implementation note for the engineer:** the exact pointer plumbing for the `prepare` callback's `processingFormat` argument and the `AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:)` initializer is fiddly and may need small adjustments to compile against the current SDK (e.g. using `AVAudioFormat(streamDescription:)` with the right pointer dance, or constructing the source `AVAudioFormat` from the player item's audio track's `formatDescriptions` instead). The *contract* is what matters: tapped audio in, stereo Float32 at `renderSampleRate` pushed into `ring` as interleaved L,R pairs. If the converter route proves troublesome, a simpler fallback is acceptable: skip resampling, push the source samples, and have `LTCAudioOutput` connect `programNode` with a format at the *source* sample rate via a mixer node that the engine resamples — but prefer the converter approach. Verify by running the app against an interface (Task 9) and confirming program audio is audible on the Track channels with no LTC corruption.

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodegen generate && xcodebuild build -scheme OnlyCue -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED. (Fix compile issues in the callback pointer plumbing as needed — see the note above.)

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/LTC/ProgramAudioTap.swift
git commit -m "feat(ltc): MTAudioProcessingTap wrapper feeding the program ring buffer"
```

---

## Task 6: `LTCAudioOutput` — second player node for program audio

**Files:**
- Modify: `OnlyCue/LTC/LTCAudioOutput.swift`

No new unit tests (live-engine path — same testing posture as the existing class; the pure pieces are covered by Tasks 3–4). Verified manually in Task 9.

- [ ] **Step 1: Implement**

In `OnlyCue/LTC/LTCAudioOutput.swift`:

1. Add a `programNode` and program-pump state next to the LTC ones:

```swift
    private let programNode = AVAudioPlayerNode()

    /// Set by the host when LTC starts with a media item present; the tap pushes
    /// into the ring buffer this drains. `nil` ⇒ no program audio (engine emits
    /// silence on the Track channels).
    private var programRing: ProgramAudioRingBuffer?
    /// Track L / Track R channel indices for the active routing (`nil` if that
    /// role isn't assigned). Set in `restartEngine`.
    private var trackLeftChannel: Int?
    private var trackRightChannel: Int?
    /// Outstanding program buffers handed to `programNode` — own lead counter,
    /// own slice of `pumpGeneration` (shared token; both pumps invalidate together).
    private var outstandingProgramBuffers = 0
    /// Frames per program buffer — same wall-clock target as the LTC buffers.
    private var programFramesPerBuffer = 0
```

2. In `init()`, attach `programNode`:

```swift
        engine.attach(playerNode)
        engine.attach(programNode)
```

3. Change `start` to accept an optional ring buffer:

```swift
    /// Begin (or restart) LTC output at `timecode`, on the device + channel the
    /// `routing` specifies. If `programRing` is non-nil and the routing assigns
    /// Track channels, the engine also plays whatever is pushed into it onto
    /// those channels. A no-op with a recorded error if `routing` has no LTC
    /// channel.
    func start(at timecode: Timecode, routing: LTCRoutingSettings, programRing: ProgramAudioRingBuffer?) {
        guard routing.ltcChannel != nil else {
            lastError = "No output channel is assigned to LTC."
            return
        }
        pendingStart = (timecode, routing)
        self.programRing = programRing
        restartEngine()
    }
```

4. In `restartEngine()`, after connecting `playerNode`, also connect `programNode` with the same `renderFormat`, set the track channels, compute `programFramesPerBuffer`, and prime the program pump:

```swift
            engine.connect(playerNode, to: engine.outputNode, format: renderFormat)
            engine.connect(programNode, to: engine.outputNode, format: renderFormat)
            self.renderFormat = renderFormat
            ltcChannel = pending.routing.ltcChannel ?? 0
            trackLeftChannel = pending.routing.trackLeftChannel
            trackRightChannel = pending.routing.trackRightChannel
            programFramesPerBuffer = LTCSchedule.framesPerBuffer(
                forTargetSeconds: bufferTargetSeconds, rate: pending.timecode.rate)
            ...
            try engine.start()
            playerNode.play()
            programNode.play()
            topUpBuffers()
            topUpProgramBuffers()
            startRefillTimer()
            isRunning = true
```

(If `programRing == nil` or no track channels are assigned, `topUpProgramBuffers` is a no-op — the engine still emits silence on those channels because nothing is scheduled on `programNode`.)

5. In `stop()`: also `programNode.stop()`, `programRing = nil`, `outstandingProgramBuffers = 0`, `trackLeftChannel = nil`, `trackRightChannel = nil`.

6. In `update(at:)`: also `programNode.stop()`, `outstandingProgramBuffers = 0`, `programRing?.flush()`, then after re-cueing the LTC schedule, `programNode.play()` and `topUpProgramBuffers()`.

7. Add the program pump (mirror the LTC pump; reuse `buffersToSchedule`):

```swift
    private func topUpProgramBuffers() {
        guard isRunningOrPriming, programRing != nil, trackLeftChannel != nil || trackRightChannel != nil else { return }
        let needed = Self.buffersToSchedule(outstanding: outstandingProgramBuffers, target: primeCount)
        for _ in 0..<needed { scheduleOneProgramBuffer() }
    }

    private func scheduleOneProgramBuffer() {
        guard isRunningOrPriming, let format = renderFormat, let ring = programRing,
              trackLeftChannel != nil || trackRightChannel != nil,
              programFramesPerBuffer > 0
        else { return }
        let interleaved = ring.drain(frameCount: programFramesPerBuffer)   // [L,R,L,R,…], always full length
        var left = [Float](repeating: 0, count: programFramesPerBuffer)
        var right = [Float](repeating: 0, count: programFramesPerBuffer)
        for i in 0..<programFramesPerBuffer {
            left[i] = interleaved[i * 2]
            right[i] = interleaved[i * 2 + 1]
        }
        var entries: [(samples: [Float], channel: Int)] = []
        if let l = trackLeftChannel { entries.append((left, l)) }
        if let r = trackRightChannel { entries.append((right, r)) }
        guard !entries.isEmpty, let pcm = Self.makeBuffer(channels: entries, format: format) else { return }
        outstandingProgramBuffers += 1
        let generation = pumpGeneration
        programNode.scheduleBuffer(pcm) { [weak self] in
            Task { @MainActor in self?.programBufferDidComplete(generation: generation) }
        }
    }

    private func programBufferDidComplete(generation: Int) {
        guard generation == pumpGeneration else { return }
        outstandingProgramBuffers = max(0, outstandingProgramBuffers - 1)
        topUpProgramBuffers()
    }
```

8. In the refill timer's event handler, also call `topUpProgramBuffers()`:

```swift
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.topUpBuffers()
                self?.topUpProgramBuffers()
            }
        }
```

9. In `handleConfigurationChange()` → `restartEngine()` path — already covered, since `restartEngine` re-creates the `programNode` connection. Make sure `restartEngine` resets `outstandingProgramBuffers = 0` alongside `outstandingBuffers = 0`.

- [ ] **Step 2: Update the one existing caller**

`OnlyCue/UI/LTCOutputHost.swift` currently calls `output.start(at:routing:)` — that won't compile until Task 7/8. To keep this task's commit building, temporarily update the call site to `output.start(at:..., routing:..., programRing: nil)`. Task 8 replaces this with the real wiring.

- [ ] **Step 3: Build + run the existing LTC tests**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/LTCAudioOutputTests -only-testing:OnlyCueTests/LTCScheduleTests`
Expected: PASS / BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OnlyCue/LTC/LTCAudioOutput.swift OnlyCue/UI/LTCOutputHost.swift
git commit -m "feat(ltc): second player node streams program audio onto track channels"
```

---

## Task 7: `PlayerEngine.setAudioMuted`

**Files:**
- Modify: `OnlyCue/Media/PlayerEngine.swift`

- [ ] **Step 1: Implement (trivial — covered by Task 8's behavior; no separate unit test)**

Add to `PlayerEngine`:

```swift
    /// Mute / unmute the player's own audio output. Used by the LTC output path
    /// to silence program audio on `AVPlayer` while it is re-routed through the
    /// LTC `AVAudioEngine`. Idempotent.
    func setAudioMuted(_ muted: Bool) {
        player.volume = muted ? 0 : 1
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme OnlyCue -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/Media/PlayerEngine.swift
git commit -m "feat(media): add setAudioMuted helper to PlayerEngine"
```

---

## Task 8: `LTCOutputHost` — gate on `isEnabled`, mute AVPlayer, manage the tap

**Files:**
- Modify: `OnlyCue/UI/LTCOutputHost.swift`

- [ ] **Step 1: Implement**

Rewrite `LTCOutputHost` to own a `ProgramAudioRingBuffer` + `ProgramAudioTap`, mute/unmute the player, and re-attach the tap when the media item changes. Note `LTCRoutingSettings.isComplete` already implies `isEnabled` (Task 1), so the existing `routingStore.settings.isComplete` guard in `refresh(playing:)` automatically respects the master switch — the new work is the player muting + tap lifecycle.

```swift
import SwiftUI
import AVFoundation

private struct LTCOutputHost: ViewModifier {

    let engine: PlayerEngine
    @ObservedObject var document: CueListDocument
    @ObservedObject private var routingStore = LTCRoutingStore.shared
    @StateObject private var output = LTCAudioOutput()

    /// One ring buffer reused for the lifetime of the host; the tap pushes into
    /// it and `LTCAudioOutput` drains it. Capacity ≈ 0.5 s of stereo @ 48 kHz —
    /// comfortably more than the engine's `primeCount` lead.
    private let programRing = ProgramAudioRingBuffer(capacityFrames: 24_000)
    @State private var programTap: ProgramAudioTap?

    private let seekThreshold: TimeInterval = 1.0
    private var settings: ProjectTimecodeSettings { document.model.timecodeSettings }

    func body(content: Content) -> some View {
        content
            .onChange(of: engine.isPlaying) { _, playing in refresh(playing: playing) }
            .onChange(of: engine.currentTime) { oldValue, newValue in
                if output.isRunning, abs(newValue - oldValue) > seekThreshold {
                    output.update(at: settings.timecode(atPlaybackSeconds: newValue))
                }
            }
            .onChange(of: routingStore.settings) { _, _ in refresh(playing: engine.isPlaying) }
            .onChange(of: settings) { _, _ in refresh(playing: engine.isPlaying) }
            // Re-point the tap when the document loads a different media item
            // while LTC is running. `engine.player.currentItem` is KVO-able; mirror
            // however other parts of the app observe it — if there's a published
            // "current media item" on the document model, key the `.onChange` off
            // that instead of polling.
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemNewAccessLogEntry)) { _ in
                if output.isRunning { reattachTapIfNeeded() }
            }
            .onDisappear { teardown() }
    }

    private func refresh(playing: Bool) {
        guard playing, routingStore.settings.isComplete else {
            teardown()
            return
        }
        // Engine on. If the routing has Track channels and there's a media item,
        // install the tap and mute the player; otherwise just run LTC.
        let routing = routingStore.settings
        if routing.hasTrackChannels, let item = engine.player.currentItem {
            installTap(on: item)
            engine.setAudioMuted(true)
            output.start(at: settings.timecode(atPlaybackSeconds: engine.currentTime),
                         routing: routing, programRing: programRing)
        } else {
            // No track routing (or no media): LTC only, player audio untouched.
            removeTap()
            engine.setAudioMuted(false)
            output.start(at: settings.timecode(atPlaybackSeconds: engine.currentTime),
                         routing: routing, programRing: nil)
        }
    }

    private func installTap(on item: AVPlayerItem) {
        programRing.flush()
        let tap = ProgramAudioTap(ring: programRing, renderSampleRate: 48_000)
        tap.attach(to: item)
        programTap = tap
    }

    private func reattachTapIfNeeded() {
        guard routingStore.settings.hasTrackChannels, let item = engine.player.currentItem else { return }
        installTap(on: item)
    }

    private func removeTap() {
        programTap?.detach()
        programTap = nil
    }

    private func teardown() {
        output.stop()
        removeTap()
        engine.setAudioMuted(false)
    }
}

extension View {
    func ltcOutput(engine: PlayerEngine, document: CueListDocument) -> some View {
        modifier(LTCOutputHost(engine: engine, document: document))
    }
}
```

> **Note on observing the media item:** the `.AVPlayerItemNewAccessLogEntry` hook above is a coarse stand-in. Prefer keying a `.onChange` off whatever the document/UI already exposes as "the loaded media item" (search the codebase for where `PlayerEngine.load(asset:)` is called from — there is likely a published media-item identity on the document model). The requirement: when the loaded media changes while LTC is running with Track routing, `installTap(on:)` must run against the new `AVPlayerItem`. Don't ship the access-log hack if a clean signal exists.

The `48_000` render sample rate matches `LTCAudioReader`'s convention and is almost certainly the engine's output rate; if `LTCAudioOutput` later exposes its actual `renderFormat.sampleRate`, thread that through to `ProgramAudioTap` instead of hardcoding. For v1 the converter handles any device rate the engine actually opens — the value passed here only needs to match what `programNode` is connected with, which is `renderFormat` (the device's rate). If they differ, audio plays at the wrong speed. **Safest:** add a `var renderSampleRate: Double?` to `LTCAudioOutput` set in `restartEngine`, and have `LTCOutputHost` recreate the tap with that value once the engine is running. If you do this, also re-`installTap` from inside `output`'s start completion — or simpler, expose `LTCAudioOutput.currentRenderSampleRate` and read it right after `start`. Pick one and make it explicit; don't leave the rate guessed.

- [ ] **Step 2: Build + run UITests + LTC tests**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS' -only-testing:OnlyCueTests/LTCAudioOutputTests -only-testing:OnlyCueUITests/AudioSettingsUITests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add OnlyCue/UI/LTCOutputHost.swift
git commit -m "feat(ltc): mute AVPlayer and route program audio through the LTC engine"
```

---

## Task 9: Manual verification + docs

**Files:**
- Modify: `docs/architecture.md`, `docs/verification.md`

- [ ] **Step 1: Manual verification against a multichannel interface**

With a multichannel audio interface connected:
1. Fresh `UserDefaults` (or `LTCRoutingStore.shared.resetToDefault()`): confirm `Settings → Audio` shows only the "Enable LTC output" toggle, off; the channel table and warnings are hidden; media plays with audio normally.
2. Toggle on: the device picker, channel table, and "No channel is assigned to LTC" warning appear.
3. Assign ch 1 = LTC, ch 2 = Track L, ch 3 = Track R on the interface. Warning clears; no "no track channels" hint.
4. Play media: confirm (a) clean LTC on ch 1 verified by an LTC reader / second app, (b) program audio audible on ch 2/3, (c) **no** program audio bleeding onto ch 1, (d) the Mac's normal output is silent for this media (AVPlayer muted).
5. Seek during playback: LTC re-cues to the new timecode; program audio follows within a fraction of a second.
6. Unplug/replug the interface mid-playback: LTC + program audio resume (config-change rebuild).
7. Set ch 2/3 back to Silent: the "Track L / Track R" hint appears; on next play, program audio is silent, LTC still clean.
8. Toggle "Enable LTC output" off: media audio returns to normal output; no LTC.

- [ ] **Step 2: Update `docs/architecture.md`**

In the "LTC and routing" section, append to the "Built so far" rundown: the `isEnabled` master switch on `LTCRoutingSettings` (default off; `isComplete` now requires it); the `AudioSettingsView` toggle gating the channel table; and the **exclusive-audio path** — when LTC runs, `LTCOutputHost` mutes `AVPlayer` and installs a `ProgramAudioTap` (`MTAudioProcessingTap` → `AVAudioConverter` → `ProgramAudioRingBuffer`) whose samples a second `AVAudioPlayerNode` in `LTCAudioOutput` plays onto the `trackLeft`/`trackRight` channels (silence there if those roles are unassigned). Update the `LTCRoutingSettings`, `Audio prefs`, `Routing playback`, and `Transport wiring` table rows accordingly. Add `ProgramAudioRingBuffer` (`OnlyCue/LTC/ProgramAudioRingBuffer.swift`) and `ProgramAudioTap` (`OnlyCue/LTC/ProgramAudioTap.swift`) as new table rows.

- [ ] **Step 3: Update `docs/verification.md`**

Add a checklist mirroring Step 1 (the manual scenarios) under the LTC section, noting that `ProgramAudioTap` / the two-node engine / AVPlayer muting are verified by running the app against an interface (the pure parts — `ProgramAudioRingBuffer`, `makeBuffer`, `LTCRoutingSettings` — are unit-tested).

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md docs/verification.md
git commit -m "docs: LTC master switch + exclusive program-audio routing"
```

- [ ] **Step 5: Full test run before opening the PR**

Run: `xcodegen generate && xcodebuild test -scheme OnlyCue -destination 'platform=macOS'`
Expected: all tests PASS. Then `swiftlint` — expected clean. Then open the PR per the `gh-pr` skill (forked OnlyCue templates — see `CLAUDE.md`), linking the spec section in the verification footer.

---

## Self-review notes

- **Spec coverage:** master switch + default off → Tasks 1, 2. Exclusive audio / no overlap → Tasks 3–8. No-track-channels = silent program audio + hint → Tasks 2 (hint), 6 (program pump skipped), 8 (`programRing: nil` path). Config-change resilience → Task 6 step 1.9. Schema (no `.cuelist` bump, tolerant decode) → Task 1. Testing posture → Tasks 1,3,4 (unit), 2 (UITest), 9 (manual). Docs → Task 9.
- **Type consistency:** `LTCRoutingSettings(isEnabled:deviceUID:channelRoles:)` (default `isEnabled`), `.settingEnabled(_:)`, `.hasTrackChannels`, `.trackLeftChannel`/`.trackRightChannel`, `isComplete = isEnabled && ltcChannel != nil` — used consistently in Tasks 1, 2, 6, 8. `LTCAudioOutput.makeBuffer(channels:format:)` + `makeBuffer(monoSamples:format:channel:)` wrapper — Tasks 3, 6. `LTCAudioOutput.start(at:routing:programRing:)` — Tasks 6, 8. `ProgramAudioRingBuffer(capacityFrames:)` / `push(interleavedStereo:)` / `drain(frameCount:)` / `flush()` — Tasks 4, 5, 6, 8. `ProgramAudioTap(ring:renderSampleRate:)` / `attach(to:)` / `detach()` — Tasks 5, 8. `PlayerEngine.setAudioMuted(_:)` — Tasks 7, 8.
- **Known soft spots flagged in-plan (not placeholders — explicit engineering judgement calls):** the `MTAudioProcessingTap` callback pointer plumbing (Task 5 note), the media-item-change signal (Task 8 note), and the render sample rate passed to `ProgramAudioTap` (Task 8 note). Each names the contract that must hold and the safe fallback.
