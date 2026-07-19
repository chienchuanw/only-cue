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
/// only explicit `Error #NN` text fails a command.
actor MA2TelnetClient {

    struct Configuration: Sendable {
        var host: String
        var port: UInt16 = 30000
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
    private var buffer = Data()

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func connect() async throws {
        disconnect()
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
            connection.stateUpdateHandler = { state in
                guard !resumed.value else { return }
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
            connection.start(queue: queue)
        }
        receiveLoop(connection)
        // Drain the console's welcome banner so it can't be mistaken for the
        // first command's response.
        try? await Task.sleep(for: .seconds(configuration.settle))
        buffer.removeAll()
    }

    func login(username: String, password: String) async throws {
        let response = try await send("login \"\(username)\" \"\(password)\"")
        guard response.localizedCaseInsensitiveContains("logged in") else {
            throw Failure.loginRejected(response: response)
        }
    }

    /// Sends one CRLF-terminated command line and returns the console's
    /// response text (trimmed), or `""` when the console stays silent.
    @discardableResult
    func send(_ command: String) async throws -> String {
        guard let connection else { throw Failure.notConnected }
        buffer.removeAll()
        connection.send(
            content: Data((command + "\r\n").utf8),
            completion: .contentProcessed { _ in }
        )

        // Wait for the first byte, then for a quiet period after the last.
        let clock = ContinuousClock()
        let firstByteDeadline = clock.now.advanced(by: .seconds(configuration.firstByteTimeout))
        while buffer.isEmpty {
            if clock.now >= firstByteDeadline { return "" }
            try await Task.sleep(for: .milliseconds(20))
        }
        var lastCount = buffer.count
        var quietSince = clock.now
        while clock.now < quietSince.advanced(by: .seconds(configuration.settle)) {
            try await Task.sleep(for: .milliseconds(20))
            if buffer.count != lastCount {
                lastCount = buffer.count
                quietSince = clock.now
            }
        }

        // Console output should be ASCII/UTF-8; anything else is surfaced
        // lossily rather than dropped.
        let text = String(bytes: buffer, encoding: .utf8)
            ?? String(bytes: buffer, encoding: .isoLatin1)
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
        buffer.removeAll()
    }

    private nonisolated func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { await self.append(data) }
            }
            if error == nil && !isComplete {
                self.receiveLoop(connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func append(_ data: Data) {
        buffer.append(data)
    }
}

/// Mutable flag shared with the `NWConnection` state handler; access is
/// serialized by the connection's dispatch queue.
private final class ResumeOnceBox: @unchecked Sendable {
    var value = false
}
