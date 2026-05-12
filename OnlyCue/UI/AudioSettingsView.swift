import SwiftUI

/// Settings → Audio pane: pick the Core Audio output device the LTC generator
/// will use and assign a role (`LTC` / `Track L` / `Track R` / `Silent`) to each
/// of its output channels. Bound to `LTCRoutingStore.shared`; nothing renders
/// audio yet — the `AVAudioEngine` playback path that consumes this routing is a
/// later leaf of epic #33.
struct AudioSettingsView: View {

    @ObservedObject private var store = LTCRoutingStore.shared
    @State private var devices: [AudioOutputDevice] = []

    private var settings: LTCRoutingSettings { store.settings }

    /// Output channels of the currently-selected device — the chosen device's
    /// count, or the default output's when "System Default" is selected, falling
    /// back to whatever the stored routing already has (min 2 so the table is
    /// never empty).
    private var channelCount: Int {
        if let uid = settings.deviceUID, let device = devices.first(where: { $0.uid == uid }) {
            return device.outputChannelCount
        }
        if settings.deviceUID == nil, let count = AudioOutputDeviceList.defaultOutput()?.outputChannelCount {
            return count
        }
        return max(2, settings.channelRoles.count)
    }

    var body: some View {
        Form {
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
                Text(
                    "The LTC generator will play onto the channel assigned “LTC”. "
                    + "A 4-channel interface can carry LTC on one channel and stereo track audio on two others."
                )
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

            if !settings.isComplete {
                Section {
                    Label("No channel is assigned to LTC.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .accessibilityIdentifier("audioRoutingWarning")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
        .accessibilityIdentifier("audioSettings")
        .onAppear {
            refreshDevices()
            reconcileChannelCount()
        }
    }

    // MARK: Bindings

    private var deviceSelection: Binding<String?> {
        Binding(
            get: { settings.deviceUID },
            set: { newUID in
                let count = channelCountForDevice(uid: newUID)
                store.update(settings.selectingDevice(uid: newUID).withDefaultRoles(forChannelCount: count))
            }
        )
    }

    private func roleSelection(forChannel channel: Int) -> Binding<ChannelRole> {
        Binding(
            get: { settings.role(forChannel: channel) },
            set: { store.update(settings.assigning($0, toChannel: channel)) }
        )
    }

    // MARK: Actions

    private func refreshDevices() {
        devices = AudioOutputDeviceList.current()
        reconcileChannelCount()
    }

    private func resetRouting() {
        store.update(LTCRoutingSettings.default.withDefaultRoles(forChannelCount: channelCount))
    }

    /// Keep `channelRoles` sized to the selected device's channel count without
    /// disturbing existing assignments (resize pads `.silent` / truncates).
    private func reconcileChannelCount() {
        let count = channelCount
        guard settings.channelRoles.count != count else { return }
        let resized = settings.channelRoles.isEmpty
            ? settings.withDefaultRoles(forChannelCount: count)
            : settings.resized(toChannelCount: count)
        store.update(resized)
    }

    private func channelCountForDevice(uid: String?) -> Int {
        if let uid, let device = devices.first(where: { $0.uid == uid }) {
            return device.outputChannelCount
        }
        if uid == nil, let count = AudioOutputDeviceList.defaultOutput()?.outputChannelCount {
            return count
        }
        return max(2, settings.channelRoles.count)
    }
}
