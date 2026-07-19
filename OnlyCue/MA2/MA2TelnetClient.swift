import Foundation
import Network

/// Telnet transport to a grandMA2 console (#683): CRLF-framed command lines
/// over TCP (port 30000 — the MA telnet remote, not classic telnet 23),
/// `login "user" "pass"`, response harvesting with a quiet-period settle,
/// `Error #` detection.
///
/// MA2's telnet output is unframed free text, so responses are harvested by
/// waiting for a quiet period after the last byte. Commands that print nothing
/// (some `/nc` forms) resolve to an empty response rather than an error —
/// only explicit `Error #NN` text fails a command. A connection that dies
/// mid-session (send error, `.failed`, remote close) fails the current and
/// all later commands instead of masquerading as console silence.
actor MA2TelnetClient {

    struct Configuration: Sendable {
        var host: String
        var port: UInt16 = 30000
        /// How long `connect()` waits for the TCP session before failing —
        /// an unreachable host can otherwise sit in `.preparing` for minutes.
        var connectTimeout: TimeInterval = 5
        /// How long to wait for the first response byte before treating the
        /// command as silently accepted.
        var firstByteTimeout: TimeInterval = 2
        /// Quiet period after the last byte before the response is complete.
        var settle: TimeInterval = 0.3
    }

    enum Failure: Error, Equatable {
        case connectionFailed(String)
        case notConnected
        case loginRejected(response: String)
        case console(command: String, response: String)
    }

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "OnlyCue.MA2TelnetClient")
    private var connection: NWConnection?
    /// Shared with the connection's receive callbacks; appends happen
    /// synchronously on the connection's serial queue so multi-chunk
    /// responses keep their arrival order.
    private nonisolated let inbound = InboundBuffer()

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func connect() async throws {
        disconnect()
        inbound.reset()
        let connection = NWConnection(
            host: NWEndpoint.Host(configuration.host),
            port: NWEndpoint.Port(rawValue: configuration.port) ?? 30000,
            using: .tcp
        )
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // The handler stays installed after resuming (for later state
            // changes) — resume exactly once. The box is only touched on the
            // connection's serial `queue`.
            let resumed = ResumeOnceBox()
            connection.stateUpdateHandler = makeStateHandler(
                connection: connection, resumed: resumed, continuation: continuation
            )
            connection.start(queue: queue)
            // Unreachable hosts can hang in `.preparing` indefinitely — cap it.
            queue.asyncAfter(deadline: .now() + configuration.connectTimeout) {
                guard !resumed.value else { return }
                resumed.value = true
                connection.cancel()
                continuation.resume(throwing: Failure.connectionFailed(
                    "connection to \(connection.endpoint) timed out"
                ))
            }
        }
        receiveLoop(connection)
        // Drain the console's welcome banner so it can't be mistaken for the
        // first command's response.
        try? await Task.sleep(for: .seconds(configuration.settle))
        inbound.clear()
    }

    func login(username: String, password: String) async throws {
        let response = try await send("login \"\(username)\" \"\(password)\"")
        guard response.localizedCaseInsensitiveContains("logged in") else {
            // The console may echo the command line back — never surface the
            // plaintext password in UI or logs.
            let redacted = password.isEmpty
                ? response
                : response.replacingOccurrences(of: password, with: "•••")
            throw Failure.loginRejected(response: redacted)
        }
    }

    /// Sends one CRLF-terminated command line and returns the console's
    /// response text (trimmed), or `""` when the console stays silent.
    @discardableResult
    func send(_ command: String) async throws -> String {
        guard let connection else { throw Failure.notConnected }
        if let failure = inbound.failure { throw Failure.connectionFailed(failure) }
        inbound.clear()
        let inbound = self.inbound
        connection.send(
            content: Data((command + "\r\n").utf8),
            completion: .contentProcessed { error in
                if let error { inbound.fail(error.localizedDescription) }
            }
        )

        // Wait for the first byte, then for a quiet period after the last.
        let clock = ContinuousClock()
        let firstByteDeadline = clock.now.advanced(by: .seconds(configuration.firstByteTimeout))
        while inbound.isEmpty {
            if let failure = inbound.failure { throw Failure.connectionFailed(failure) }
            if clock.now >= firstByteDeadline { return "" }
            try await Task.sleep(for: .milliseconds(20))
        }
        var lastCount = inbound.count
        var quietSince = clock.now
        while clock.now < quietSince.advanced(by: .seconds(configuration.settle)) {
            try await Task.sleep(for: .milliseconds(20))
            let count = inbound.count
            if count != lastCount {
                lastCount = count
                quietSince = clock.now
            }
        }

        // Console output should be ASCII/UTF-8; anything else is surfaced
        // lossily rather than dropped.
        let data = inbound.snapshot()
        let text = String(bytes: data, encoding: .utf8)
            ?? String(bytes: data, encoding: .isoLatin1)
            ?? ""
        let response = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if response.contains("Error #") {
            throw Failure.console(command: command, response: response)
        }
        return response
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        inbound.reset()
    }

    /// Builds the connect-phase state handler: resumes `continuation` exactly
    /// once for the initial ready/failed outcome, then flips to marking the
    /// established session as dead (via `inbound.fail`) on later failures.
    private nonisolated func makeStateHandler(
        connection: NWConnection,
        resumed: ResumeOnceBox,
        continuation: CheckedContinuation<Void, Error>
    ) -> @Sendable (NWConnection.State) -> Void {
        let inbound = self.inbound
        return { state in
            if resumed.value {
                // Established session died — fail every later command
                // instead of letting them time out as "console silence".
                switch state {
                case .failed(let error):
                    inbound.fail(error.localizedDescription)
                case .waiting(let error):
                    inbound.fail(error.localizedDescription)
                case .cancelled:
                    inbound.fail("connection closed")
                default:
                    break
                }
                return
            }
            switch state {
            case .ready:
                resumed.value = true
                continuation.resume()
            case .failed(let error):
                resumed.value = true
                connection.cancel()
                continuation.resume(throwing: Failure.connectionFailed(error.localizedDescription))
            case .waiting(let error):
                // Connection refused lands here (Network retries forever
                // by default) — for a push there is no point waiting.
                resumed.value = true
                connection.cancel()
                continuation.resume(throwing: Failure.connectionFailed(error.localizedDescription))
            case .cancelled:
                resumed.value = true
                continuation.resume(throwing: Failure.connectionFailed("cancelled"))
            default:
                break
            }
        }
    }

    private nonisolated func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [inbound] data, _, isComplete, error in
            if let data, !data.isEmpty {
                // Synchronous append on the connection's serial queue keeps
                // multi-chunk responses in arrival order.
                inbound.append(data)
            }
            if error == nil && !isComplete {
                self.receiveLoop(connection)
            } else {
                if let error {
                    inbound.fail(error.localizedDescription)
                } else if isComplete {
                    inbound.fail("connection closed by console")
                }
                connection.cancel()
            }
        }
    }
}

/// Inbound byte buffer plus a sticky failure flag, shared between the actor
/// and the `NWConnection` callbacks. All access is behind one lock; appends
/// come from the connection's serial queue so ordering is preserved.
private final class InboundBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var failureMessage: String?

    var count: Int { lock.withLock { data.count } }
    var isEmpty: Bool { lock.withLock { data.isEmpty } }
    var failure: String? { lock.withLock { failureMessage } }

    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    func snapshot() -> Data { lock.withLock { data } }
    func clear() { lock.withLock { data.removeAll() } }

    /// First failure wins; later ones would only be knock-on effects.
    func fail(_ message: String) {
        lock.withLock { if failureMessage == nil { failureMessage = message } }
    }

    func reset() {
        lock.withLock {
            data.removeAll()
            failureMessage = nil
        }
    }
}

/// Mutable flag shared with the `NWConnection` state handler; access is
/// serialized by the connection's dispatch queue.
private final class ResumeOnceBox: @unchecked Sendable {
    var value = false
}
