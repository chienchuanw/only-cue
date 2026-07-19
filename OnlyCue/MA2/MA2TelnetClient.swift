import Foundation
import Network

/// Telnet transport to a grandMA2 console (#683): CRLF-framed command lines
/// over TCP (port 30000 — the MA telnet remote, not classic telnet 23),
/// `login "user" "pass"`, response harvesting with a quiet-period settle,
/// `Error #` detection.
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

    init(configuration: Configuration) {
        fatalError("unimplemented")
    }

    func connect() async throws {
        fatalError("unimplemented")
    }

    func login(username: String, password: String) async throws {
        fatalError("unimplemented")
    }

    @discardableResult
    func send(_ command: String) async throws -> String {
        fatalError("unimplemented")
    }

    func disconnect() {
        fatalError("unimplemented")
    }
}
