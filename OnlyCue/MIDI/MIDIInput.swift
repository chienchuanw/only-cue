import CoreMIDI
import Foundation
import Observation

/// Receive-only CoreMIDI input. Owns one `MIDIClientRef` + one input port,
/// connects to the single source the user picked (by `kMIDIPropertyUniqueID`),
/// parses each packet with `MIDIMessage.parse`, and hands recognised messages
/// to `onMessage` on the main actor. Unrecognised bytes are dropped; everything
/// that parses is appended to `recentMessages` so the monitor sheet
/// (`Tools → MIDI Monitor…`) shows traffic even when nothing is bound.
///
/// This is the untested edge of the MIDI subsystem, deliberately kept thin —
/// the same split `OSCServer` uses, where the socket code is manual-verified
/// and all decision logic lives in pure, unit-tested types (`MIDIMessage`,
/// `MIDISignal`, `MIDIDispatchGate`, `MIDICommandDispatcher`).
///
/// No entitlement is required to open a MIDI client: the app is not sandboxed
/// (ADR-007), and CoreMIDI input needs no privacy prompt on macOS.
///
/// Threading: the CoreMIDI read block runs on a CoreMIDI-owned thread. It only
/// parses bytes, then hops to the main actor to touch observable state and call
/// `onMessage`, so nothing mutable is shared across threads.
@MainActor
@Observable
final class MIDIInput {

    private static let recentMessagesCap = 50

    private(set) var isConnected = false
    private(set) var connectedName: String?
    private(set) var lastError: String?
    /// Newest-first ring buffer of formatted monitor lines, capped.
    private(set) var recentMessages: [String] = []

    var onMessage: ((MIDIMessage) -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef?

    // MARK: - Lifecycle

    /// Connects to the source whose unique ID matches `inputUID`. Passing nil
    /// (or an ID no longer present — the surface was unplugged) tears the
    /// connection down and leaves the client alive, so a later hot-plug of the
    /// same device reconnects without recreating anything.
    func start(inputUID: String?) {
        ensureClientAndPort()
        disconnectSource()
        guard let inputUID, let source = Self.source(withUID: inputUID) else {
            isConnected = false
            connectedName = nil
            return
        }
        let status = MIDIPortConnectSource(port, source, nil)
        guard status == noErr else {
            lastError = "MIDIPortConnectSource failed (\(status))"
            isConnected = false
            connectedName = nil
            return
        }
        connectedSource = source
        isConnected = true
        connectedName = Self.displayName(of: source)
        lastError = nil
    }

    func stop() {
        disconnectSource()
        isConnected = false
        connectedName = nil
    }

    private func disconnectSource() {
        if let connectedSource {
            MIDIPortDisconnectSource(port, connectedSource)
        }
        connectedSource = nil
    }

    private func ensureClientAndPort() {
        guard client == MIDIClientRef() else { return }
        var newClient = MIDIClientRef()
        // The notify block fires on hot-plug; re-running `start` re-resolves the
        // selected UID, so replugging the surface restores the connection.
        let clientStatus = MIDIClientCreateWithBlock("OnlyCue" as CFString, &newClient) { [weak self] notification in
            guard notification.pointee.messageID == .msgObjectAdded
                    || notification.pointee.messageID == .msgObjectRemoved else { return }
            Task { @MainActor [weak self] in self?.handleHotPlug() }
        }
        guard clientStatus == noErr else {
            lastError = "MIDIClientCreateWithBlock failed (\(clientStatus))"
            return
        }
        client = newClient

        var newPort = MIDIPortRef()
        let portStatus = MIDIInputPortCreateWithProtocol(
            client, "OnlyCue Input" as CFString, ._1_0, &newPort
        ) { [weak self] eventList, _ in
            let messages = Self.messages(in: eventList)
            guard !messages.isEmpty else { return }
            Task { @MainActor [weak self] in messages.forEach { self?.ingest($0) } }
        }
        guard portStatus == noErr else {
            lastError = "MIDIInputPortCreateWithProtocol failed (\(portStatus))"
            return
        }
        port = newPort
    }

    /// A device appeared or vanished — re-resolve the user's chosen UID so a
    /// replug reconnects and an unplug reports "not connected" rather than
    /// silently pretending to listen.
    private func handleHotPlug() {
        start(inputUID: MIDIMapStore.shared.selectedInputUID)
    }

    // MARK: - Main-actor state

    private func ingest(_ message: MIDIMessage) {
        appendRecent(message)
        onMessage?(message)
    }

    private func appendRecent(_ message: MIDIMessage) {
        recentMessages.insert(Self.formatLine(for: message), at: 0)
        if recentMessages.count > Self.recentMessagesCap {
            recentMessages.removeLast(recentMessages.count - Self.recentMessagesCap)
        }
    }

    /// Empties the monitor tail. Doesn't touch the connection — purely a
    /// view-side "clear what I've seen so far".
    func clearRecentMessages() {
        recentMessages.removeAll()
    }

    /// One-line rendering for the monitor tail, column-aligned so a stream of
    /// fader moves reads as a table. Pure — pinned by `MIDIMonitorTests`.
    nonisolated static func formatLine(for message: MIDIMessage) -> String {
        switch message {
        case let .note(channel, number, velocity):
            "Note  ch\(channel)  #\(number)  \(velocity)"
        case let .controlChange(channel, number, value):
            "CC    ch\(channel)  #\(number)  \(value)"
        }
    }

    // MARK: - Device discovery

    /// Every connected MIDI source, as `(uid, name)` for the Settings picker.
    nonisolated static func availableSources() -> [(uid: String, name: String)] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let source = MIDIGetSource(index)
            guard let uid = uniqueID(of: source) else { return nil }
            return (uid: uid, name: displayName(of: source))
        }
    }

    nonisolated private static func source(withUID uid: String) -> MIDIEndpointRef? {
        (0..<MIDIGetNumberOfSources())
            .map(MIDIGetSource)
            .first { uniqueID(of: $0) == uid }
    }

    nonisolated private static func uniqueID(of endpoint: MIDIEndpointRef) -> String? {
        var value: Int32 = 0
        guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &value) == noErr else { return nil }
        return String(value)
    }

    nonisolated private static func displayName(of endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr,
              let name
        else { return "Unknown MIDI device" }
        return name.takeRetainedValue() as String
    }

    // MARK: - Packet walking

    /// Flattens a `MIDIEventList` into the messages OnlyCue understands.
    /// Universal MIDI Packets in the MIDI 1.0 protocol carry the legacy status
    /// bytes in the low three bytes of each 32-bit word, so we re-emit those to
    /// `MIDIMessage.parse` rather than duplicating status decoding here.
    nonisolated private static func messages(in eventList: UnsafePointer<MIDIEventList>) -> [MIDIMessage] {
        var result: [MIDIMessage] = []
        var packet = eventList.pointee.packet
        for _ in 0..<eventList.pointee.numPackets {
            withUnsafeBytes(of: packet.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                for index in 0..<Int(packet.wordCount) where index < words.count {
                    if let message = message(fromUMPWord: words[index]) { result.append(message) }
                }
            }
            packet = MIDIEventPacketNext(&packet).pointee
        }
        return result
    }

    /// Decodes one MIDI 1.0 Universal MIDI Packet word (`0x2` message type):
    /// byte layout is `[type|group][status][data1][data2]`.
    nonisolated private static func message(fromUMPWord word: UInt32) -> MIDIMessage? {
        guard (word >> 28) == 0x2 else { return nil }   // MIDI 1.0 channel voice
        let status = UInt8((word >> 16) & 0xFF)
        let data1 = UInt8((word >> 8) & 0x7F)
        let data2 = UInt8(word & 0x7F)
        return MIDIMessage.parse([status, data1, data2])
    }
}
