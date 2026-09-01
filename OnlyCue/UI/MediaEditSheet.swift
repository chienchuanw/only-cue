import SwiftUI

/// Modal sheet for editing a single `MediaItem`'s user-facing metadata:
/// alternate display name, start-timecode offset, per-clip LTC mute, and
/// per-clip source-audio mode. Save commits all four fields atomically through
/// `CueCommands.updateMediaItem` (single undo step). Cancel discards drafts.
///
/// The TC field uses the project framerate for parsing and display, matching
/// `MediaTimecodeRow`. Per-media framerate is intentionally out of scope.
struct MediaEditSheet: View {

    let item: MediaItem
    let framerate: SMPTEFramerate
    let onSave: (_ alternateName: String?, _ startFrames: Int, _ muted: Bool, _ playsOriginal: Bool) -> Void
    let onCancel: () -> Void
    /// Force a fresh LTC scan for this clip (clears the cache + remembered value
    /// so detection re-runs). Supplied by the presenter, which holds `document`.
    var onRedetectLTC: () -> Void = {}
    /// Forget this clip's remembered LTC (#754). Supplied by the presenter.
    var onClearLTC: () -> Void = {}
    /// Records which channel carries LTC (#793). Applied immediately rather
    /// than on Save — the status line re-resolves against the new channel,
    /// so the change has to have landed to be worth showing. Supplied by the
    /// presenter, which holds `document` and the undo manager.
    var onSelectLTCChannel: (LTCChannelSelection) -> Void = { _ in }

    @State private var nameDraft: String = ""
    @State private var tcDraft: String = ""
    @State private var mutedDraft: Bool = false
    @State private var playsOriginalDraft: Bool = false
    @State private var tcInvalid: Bool = false
    /// The resolved LTC for this clip (detected, or the remembered fallback, #754).
    /// Drives the LTC status line, and its channel feeds the music-only preview.
    @State private var resolvedTrack: StripedTimecodeTrack?
    @State private var detecting = true
    /// Bumped by Re-detect / Clear to re-run the resolve `.task`.
    @State private var fetchToken = UUID()
    /// The picker's displayed value. `item` is a snapshot the presenter took
    /// when the sheet opened and never updates, so this is the source of
    /// truth after the initial sync.
    @State private var channelDraft: LTCChannelSelection = .auto
    /// How many channels the file has, for the picker's rows. 0 until the
    /// probe returns, which is why the loop below is over an empty range then.
    @State private var channelCount = 0

    private var ltcChannel: Int? { resolvedTrack?.ltcChannel }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Media")
                .font(.headline)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            MediaPreviewStrip(
                kind: item.media.kind,
                bookmarkData: item.media.bookmarkData,
                excludingChannel: ltcChannel
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
                    // A `prompt:` renders inside the box; passing the hint as the
                    // TextField's title instead makes macOS draw it as an external
                    // label that eats the field's width (#649).
                    TextField("Name", text: $nameDraft, prompt: Text(item.media.displayName))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("mediaEditNameField")
                }
                LabeledContent("Start timecode") {
                    // In-field `prompt:` (not a title) so `.frame(width:)` goes
                    // entirely to the input box, wide enough for HH:MM:SS:FF (#649).
                    TextField("Start timecode", text: $tcDraft, prompt: Text("HH:MM:SS:FF"))
                        .labelsHidden()
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
                Section("LTC") {
                    Picker("Channel", selection: $channelDraft) {
                        Text(autoChannelLabel).tag(LTCChannelSelection.auto)
                        // Array(...) not a bare 0..<channelCount: SwiftUI treats a bare range
                        // as constant and does not re-render when the probe returns.
                        ForEach(Array(0..<channelCount), id: \.self) { index in
                            Text("Channel \(index + 1)").tag(LTCChannelSelection.channel(index))
                        }
                        Text("No LTC").tag(LTCChannelSelection.none)
                    }
                    .accessibilityIdentifier("mediaEditLTCChannelPicker")
                    .onChange(of: channelDraft) { _, new in
                        onSelectLTCChannel(new)
                        fetchToken = UUID()   // re-resolve the status line against the new choice
                    }
                    LabeledContent("Status") {
                        Text(ltcStatusText)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("mediaEditLTCStatus")
                    }
                    HStack {
                        Button("Re-detect") { redetect() }
                            .accessibilityIdentifier("mediaEditLTCRedetect")
                        Button("Clear") { clearLTC() }
                            .disabled(item.rememberedLTC == nil)
                            .accessibilityIdentifier("mediaEditLTCClear")
                    }
                    Toggle("Mute LTC for this clip", isOn: $mutedDraft)
                        .accessibilityIdentifier("mediaEditMuteToggle")
                    Toggle("Play original source audio (with timecode)", isOn: $playsOriginalDraft)
                        .help("Off = music only (mutes the detected timecode channel)")
                        .accessibilityIdentifier("mediaEditSourceAudioToggle")
                }
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
        .task(id: fetchToken) {
            detecting = true
            channelCount = await MediaImporter.audioChannelCount(for: item)
            resolvedTrack = await MediaImporter.resolvedStripedTimecode(for: item)
            detecting = false
        }
    }

    /// Names what Auto actually found, so the user can accept it or override
    /// it from the same list without first reading the Status row.
    private var autoChannelLabel: String {
        guard let channel = resolvedTrack?.ltcChannel, channelDraft == .auto else { return "Auto" }
        return "Auto (detected: Channel \(channel + 1))"
    }

    private var ltcStatusText: String {
        if detecting { return "Detecting…" }
        guard let track = resolvedTrack else { return "Not found" }
        let prefix = item.rememberedLTC == nil ? "Detected" : "Remembered"
        let tc = track.timecode(atPlaybackSeconds: track.anchorPlaybackSeconds).displayString
        var line = "\(prefix) · channel \(track.ltcChannel + 1) · \(tc)"
        // Present only once the full-file pass has measured something. A range
        // visibly shorter than the media is also how a truncated/discontinuous
        // stripe announces itself (spec section 2).
        if let extent = LTCExtentLabel.text(validFrom: track.validFrom, validUntil: track.validUntil) {
            line += " · \(extent)"
        }
        return line
    }

    private func redetect() {
        onRedetectLTC()          // presenter clears the cache + remembered value
        fetchToken = UUID()      // re-run the resolve task against the fresh scan
    }

    private func clearLTC() {
        onClearLTC()
        fetchToken = UUID()
    }

    private func syncDraftsFromItem() {
        nameDraft = item.alternateName ?? ""
        tcDraft = Timecode(frameCount: item.startTimecodeFrames, rate: framerate).displayString
        mutedDraft = item.ltcMuted
        playsOriginalDraft = item.playsOriginalSourceAudio
        tcInvalid = false
        channelDraft = item.ltcChannelSelection
    }

    private func commit() {
        guard let parsed = Timecode.parse(tcDraft, rate: framerate) else {
            tcInvalid = true
            return
        }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternate = trimmed.isEmpty ? nil : trimmed
        onSave(alternate, parsed.frameCount, mutedDraft, playsOriginalDraft)
    }
}
