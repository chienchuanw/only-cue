import Foundation
import Network
import Observation

/// Receive-only OSC server over UDP. Wraps an `NWListener`; parses each
/// datagram with `OSCParser`, maps it with `OSCCommand.from(_:)`, and hands
/// recognised commands to `onCommand` on the main actor. Unrecognised
/// datagrams are still appended to `recentMessages` so the OSC monitor sheet
/// (`Tools → OSC Monitor…`) can show "received but unhandled" traffic.
///
/// No App Sandbox entitlement is needed to bind an incoming UDP port (the app
/// is not sandboxed — ADR-007). macOS shows a one-time firewall prompt the
/// first time the listener binds; that's expected and out of OnlyCue's
/// control.
///
/// Threading: `NWListener` / `NWConnection` callbacks run on the private
/// `queue`. The connection-accept and receive-loop methods are `nonisolated`
/// (they only touch the `Sendable` `NWConnection` and the immutable `queue`);
/// everything that mutates observable state or invokes `onCommand` hops to
/// the main actor via `ingest(_:)`.
@MainActor
@Observable
final class OSCServer {

    // `nonisolated` so `OSCServerSettings.defaultPort` (a nonisolated `enum`)
    // can derive its value from here — an immutable Sendable constant has no
    // need for the class's `@MainActor` isolation. Without it: "main
    // actor-isolated static property 'defaultPort' can not be referenced from
    // a nonisolated context" (an error under the Swift 6 language mode).
    nonisolated static let defaultPort: UInt16 = 8000
    private static let recentMessagesCap = 50

    private(set) var isListening = false
    private(set) var lastError: String?
    /// Newest-first ring buffer of "addr arg1 arg2 …" strings, capped.
    private(set) var recentMessages: [String] = []

    var onCommand: ((OSCCommand) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "OnlyCue.OSCServer")

    func start(port: UInt16) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port \(port)"
            return
        }
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handleListenerState(state) }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    // MARK: - Main-actor state

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            lastError = nil
        case .failed(let error):
            isListening = false
            lastError = error.localizedDescription
        case .cancelled:
            isListening = false
        default:
            break
        }
    }

    private func ingest(_ data: Data) {
        guard let message = OSCParser.parse(data) else { return }
        appendRecent(message)
        if let command = OSCCommand.from(message) {
            onCommand?(command)
        }
    }

    private func appendRecent(_ message: OSCMessage) {
        recentMessages.insert(Self.formatLine(for: message), at: 0)
        if recentMessages.count > Self.recentMessagesCap {
            recentMessages.removeLast(recentMessages.count - Self.recentMessagesCap)
        }
    }

    /// Empties the monitor tail. Doesn't touch the listener — purely a
    /// view-side "clear what I've seen so far".
    func clearRecentMessages() {
        recentMessages.removeAll()
    }

    /// One-line rendering of a received message for the monitor tail:
    /// `"<address> <arg1> <arg2> …"`, or just `"<address>"` with no arguments.
    nonisolated static func formatLine(for message: OSCMessage) -> String {
        let argsDescription = message.arguments.map(describe).joined(separator: " ")
        return argsDescription.isEmpty
            ? message.addressPattern
            : "\(message.addressPattern) \(argsDescription)"
    }

    nonisolated private static func describe(_ argument: OSCArgument) -> String {
        switch argument {
        case .int32(let value): String(value)
        case .float32(let value): String(value)
        case .string(let value): "\"\(value)\""
        case .true: "T"
        case .false: "F"
        case .null: "N"
        case .impulse: "I"
        }
    }

    // MARK: - Off-main connection plumbing

    nonisolated private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    nonisolated private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                // TODO: rate-limit datagrams — a flood currently queues
                // unbounded main-actor tasks (fine for a trusted LAN in v1).
                Task { @MainActor [weak self] in self?.ingest(data) }
            }
            if error == nil {
                self?.receive(on: connection)
            } else {
                // Connection errored or closed — release it rather than
                // leaving a stale socket around.
                connection.cancel()
            }
        }
    }
}
