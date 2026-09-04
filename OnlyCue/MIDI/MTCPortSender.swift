import CoreMIDI
import Foundation

/// The CoreMIDI wiring behind MTC output (epic #794): one client, one output
/// port, one resolved destination, and the `MIDISendEventList` calls.
///
/// Split from `MTCOutput` so that type is purely about *when* to send and this
/// one is purely about *how*. Everything here is hardware-facing and therefore
/// not headless-testable; the bit-packing it hands over is pure and tested in
/// `MIDIUniversalPacket`, and the timing is pure and tested in `MTCSchedule`.
/// The same split `MIDIInput` uses, applied to the send direction.
///
/// No entitlement is required to open a MIDI client: the app is not sandboxed
/// (ADR-007), and CoreMIDI output needs no privacy prompt on macOS.
@MainActor
final class MTCPortSender {

    /// One event to schedule: the UMP words and the host time they are due.
    /// A `timestamp` of 0 means "deliver immediately".
    struct Event {
        let timestamp: MIDITimeStamp
        let words: [UInt32]
    }

    /// Display name of the resolved destination, or `nil` when unresolved.
    private(set) var connectedName: String?
    /// The most recent failure, for `MTCOutput` to republish to the UI.
    private(set) var lastError: String?
    /// Whether a live destination is currently resolved.
    var isResolved: Bool { destination != nil }

    // Transport handles. `nonisolated(unsafe)` so the nonisolated `deinit` can
    // dispose them: both are only ever mutated from the main actor, and
    // CoreMIDI's dispose calls are themselves thread-safe.
    nonisolated(unsafe) private var client = MIDIClientRef()
    nonisolated(unsafe) private var port = MIDIPortRef()

    private var destination: MIDIEndpointRef?
    private var resolvedUID: String?

    /// Called when a hot-plug notification arrives, after the chosen UID has
    /// been re-resolved — lets the owner refresh published state.
    var onEndpointsChanged: (() -> Void)?

    /// Bytes of scratch space for one `MIDIEventList`. A refill window carries a
    /// couple of dozen quarter-frames (16 bytes each), so this is generous; the
    /// send loop flushes rather than truncating if it ever is not.
    private let listCapacity = 4096

    /// The client and port live as long as the owner does — `MTCOutput.stop()`
    /// only halts the stream, so re-arming is cheap. Dispose them here or every
    /// closed document window leaks one of each for the process lifetime, the
    /// same line `MIDIInput` draws.
    deinit {
        if port != MIDIPortRef() { MIDIPortDispose(port) }
        if client != MIDIClientRef() { MIDIClientDispose(client) }
    }

    // MARK: - Resolution

    /// Resolve `uid` to a live destination, opening the client and port on first
    /// use. Records an error and returns `false` when the destination is missing
    /// — the "unplugged mid-show" case the status row surfaces.
    @discardableResult
    func resolve(uid: String?) -> Bool {
        ensureClientAndPort()
        guard port != MIDIPortRef() else { return false }   // `lastError` already says why
        guard let uid else {
            clearDestination(uid: nil, error: "No MIDI destination is selected.")
            return false
        }
        guard let endpoint = Self.destination(withUID: uid) else {
            clearDestination(uid: uid, error: "The selected MIDI destination is unavailable.")
            return false
        }
        destination = endpoint
        resolvedUID = uid
        connectedName = Self.displayName(of: endpoint)
        lastError = nil
        return true
    }

    private func clearDestination(uid: String?, error: String) {
        destination = nil
        resolvedUID = uid
        connectedName = nil
        lastError = error
    }

    // MARK: - Sending

    /// Build one `MIDIEventList` from `events` and send it.
    ///
    /// The list is assembled in a raw allocation rather than a `MIDIEventList`
    /// value because the struct's inline storage holds a single packet, while a
    /// refill window carries a couple of dozen. `MIDIEventListAdd` returns null
    /// when the buffer is full, so a batch that would overflow is flushed and a
    /// fresh list started, rather than being silently truncated.
    func send(_ events: [Event]) {
        guard let destination, port != MIDIPortRef(), !events.isEmpty else { return }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: listCapacity, alignment: MemoryLayout<MIDIEventList>.alignment
        )
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)

        var packet = MIDIEventListInit(list, ._1_0)
        var pending = false

        for event in events {
            if let added = add(event, to: list, after: packet) {
                packet = added
                pending = true
                continue
            }
            // Buffer full — flush what fits, then restart the list with this event.
            if pending { flush(list, to: destination) }
            packet = MIDIEventListInit(list, ._1_0)
            pending = false
            if let retried = add(event, to: list, after: packet) {
                packet = retried
                pending = true
            }
        }

        if pending { flush(list, to: destination) }
    }

    private func add(
        _ event: Event,
        to list: UnsafeMutablePointer<MIDIEventList>,
        after packet: UnsafeMutablePointer<MIDIEventPacket>
    ) -> UnsafeMutablePointer<MIDIEventPacket>? {
        event.words.withUnsafeBufferPointer { words in
            guard let base = words.baseAddress else { return packet }
            return MIDIEventListAdd(list, listCapacity, packet, event.timestamp, words.count, base)
        }
    }

    private func flush(_ list: UnsafeMutablePointer<MIDIEventList>, to destination: MIDIEndpointRef) {
        let status = MIDISendEventList(port, destination, list)
        if status == noErr {
            if lastError != nil { lastError = nil }
        } else {
            lastError = "MIDISendEventList failed (\(status))"
        }
    }

    // MARK: - Client and port

    /// Idempotent and — importantly — *retryable*. The port is what matters, so
    /// that is what gates the early return: if the client was created but the
    /// port was not, a later call retries the port against the surviving client
    /// instead of latching MTC off for the life of the process. The same trap
    /// `MIDIInput.ensureClientAndPort` documents.
    private func ensureClientAndPort() {
        guard port == MIDIPortRef() else { return }
        guard client == MIDIClientRef() else {
            createPort()
            return
        }
        var newClient = MIDIClientRef()
        // The notify block fires on hot-plug; re-resolving the selected UID means
        // replugging the interface restores the connection.
        let status = MIDIClientCreateWithBlock("OnlyCue MTC" as CFString, &newClient) { [weak self] notification in
            guard notification.pointee.messageID == .msgObjectAdded
                    || notification.pointee.messageID == .msgObjectRemoved else { return }
            Task { @MainActor [weak self] in self?.handleHotPlug() }
        }
        guard status == noErr else {
            lastError = "MIDIClientCreateWithBlock failed (\(status))"
            return
        }
        client = newClient
        createPort()
    }

    private func createPort() {
        var newPort = MIDIPortRef()
        let status = MIDIOutputPortCreate(client, "OnlyCue MTC Output" as CFString, &newPort)
        guard status == noErr else {
            lastError = "MIDIOutputPortCreate failed (\(status))"
            return
        }
        port = newPort
    }

    /// A device appeared or vanished — re-resolve the chosen UID so a replug
    /// reconnects and an unplug reports it rather than silently sending nowhere.
    private func handleHotPlug() {
        guard let resolvedUID else { return }
        resolve(uid: resolvedUID)
        onEndpointsChanged?()
    }

    // MARK: - Discovery

    /// Every connected MIDI destination, as `(uid, name)` for the Settings
    /// picker. The twin of `MIDIInput.availableSources()`, over destinations.
    nonisolated static func availableDestinations() -> [(uid: String, name: String)] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard let uid = uniqueID(of: endpoint) else { return nil }
            return (uid: uid, name: displayName(of: endpoint))
        }
    }

    nonisolated private static func destination(withUID uid: String) -> MIDIEndpointRef? {
        (0..<MIDIGetNumberOfDestinations())
            .map(MIDIGetDestination)
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
}
