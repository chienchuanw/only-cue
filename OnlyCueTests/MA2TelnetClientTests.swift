import Network
import XCTest
@testable import OnlyCue

/// #683 — the telnet transport to the console: CRLF-framed command lines over
/// TCP 30000, `login "user" "pass"`, response harvesting with a quiet-period
/// settle, `Error #` detection. Exercised against an in-process loopback TCP
/// fixture; the real console is only touched in plan step 13.
final class MA2TelnetClientTests: XCTestCase {

    /// Loopback TCP server: accepts one telnet session, greets with a banner,
    /// answers each received CRLF line via `handler` (nil = stay silent).
    ///
    /// `bannerDelay` holds the greeting back, so "the banner arrives late" is a
    /// fixture setting rather than a race against machine load (#816).
    private final class Fixture: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "MA2TelnetClientTests.Fixture")
        private var connections: [NWConnection] = []
        private var lineBuffer = Data()
        private var lines: [String] = []
        private let handler: @Sendable (String) -> String?
        private let bannerDelay: TimeInterval

        init(bannerDelay: TimeInterval = 0, handler: @escaping @Sendable (String) -> String?) throws {
            self.handler = handler
            self.bannerDelay = bannerDelay
            listener = try NWListener(using: .tcp, on: .any)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                if case .ready = state { ready.signal() }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            XCTAssertEqual(ready.wait(timeout: .now() + 2), .success, "fixture listener never became ready")
        }

        var port: UInt16 { listener.port?.rawValue ?? 0 }

        /// Every complete CRLF-terminated line received, in order.
        var receivedLines: [String] { queue.sync { lines } }

        func stop() {
            queue.sync {
                connections.forEach { $0.cancel() }
                connections.removeAll()
            }
            listener.cancel()
        }

        private func accept(_ connection: NWConnection) {
            connections.append(connection)
            connection.start(queue: queue)
            // Real consoles greet with a banner before login; the client must
            // not mistake it for a command response.
            let greet = {
                connection.send(
                    content: Data("Welcome to grandMA2\r\n".utf8),
                    completion: .contentProcessed { _ in }
                )
            }
            if bannerDelay > 0 {
                queue.asyncAfter(deadline: .now() + bannerDelay, execute: greet)
            } else {
                greet()
            }
            receiveLoop(connection)
        }

        private func receiveLoop(_ connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data { self.ingest(data, on: connection) }
                if error == nil && !isComplete {
                    self.receiveLoop(connection)
                } else {
                    connection.cancel()
                }
            }
        }

        private func ingest(_ data: Data, on connection: NWConnection) {
            lineBuffer.append(data)
            while let terminator = lineBuffer.range(of: Data("\r\n".utf8)) {
                let line = String(bytes: lineBuffer[..<terminator.lowerBound], encoding: .utf8) ?? ""
                lineBuffer.removeSubrange(..<terminator.upperBound)
                lines.append(line)
                if let response = handler(line) {
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
                }
            }
        }
    }

    /// Fast timings for loopback: real defaults (0.3 s settle etc.) would just
    /// slow the suite.
    private func client(port: UInt16) -> MA2TelnetClient {
        MA2TelnetClient(configuration: .init(
            host: "127.0.0.1",
            port: port,
            firstByteTimeout: 0.3,
            settle: 0.05
        ))
    }

    func test_send_framesCRLF_andReturnsResponse() async throws {
        let fixture = try Fixture { line in
            line == "Delete Sequence 18 /nc" ? "Deleted 1 Sequences\r\n" : nil
        }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        let response = try await client.send("Delete Sequence 18 /nc")

        XCTAssertTrue(response.contains("Deleted 1 Sequences"))
        // The fixture only surfaces complete CRLF lines — receiving the
        // command back proves the client terminated it with \r\n.
        XCTAssertEqual(fixture.receivedLines, ["Delete Sequence 18 /nc"])
        await client.disconnect()
    }

    func test_login_sendsQuotedCredentials_andAcceptsLoggedInResponse() async throws {
        let fixture = try Fixture { line in
            line == "login \"john\" \"sesame\"" ? "Logged in as User 'john'\r\n" : nil
        }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        try await client.login(username: "john", password: "sesame")

        XCTAssertEqual(fixture.receivedLines, ["login \"john\" \"sesame\""])
        await client.disconnect()
    }

    func test_login_rejectedResponse_throws() async throws {
        let fixture = try Fixture { _ in "no login\r\n" }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        do {
            try await client.login(username: "john", password: "wrong")
            XCTFail("expected loginRejected")
        } catch let failure as MA2TelnetClient.Failure {
            XCTAssertEqual(failure, .loginRejected(response: "no login"))
        }
        await client.disconnect()
    }

    func test_login_rejection_surfacesConsoleTextVerbatim() async throws {
        // The console echoes the command line back, and "admin" is a substring of
        // "administrator" — any password-blanking would corrupt the rejection
        // message into "•••istrator" (#690).
        let fixture = try Fixture { _ in
            "Executing : Login \"administrator\" \"admin\"\r\nLogin incorrect\r\n"
        }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        do {
            try await client.login(username: "administrator", password: "admin")
            XCTFail("expected loginRejected")
        } catch let failure as MA2TelnetClient.Failure {
            guard case .loginRejected(let response) = failure else {
                return XCTFail("unexpected failure \(failure)")
            }
            XCTAssertTrue(response.contains("administrator"), "got: \(response)")
            XCTAssertFalse(response.contains("•••"), "got: \(response)")
        }
        await client.disconnect()
    }

    func test_consoleErrorResponse_throwsWithCommandAndText() async throws {
        let fixture = try Fixture { _ in "Error #12 at line 1\r\n" }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        do {
            _ = try await client.send("Import \"x\" At 18 /nc")
            XCTFail("expected console failure")
        } catch let failure as MA2TelnetClient.Failure {
            XCTAssertEqual(failure, .console(
                command: "Import \"x\" At 18 /nc",
                response: "Error #12 at line 1"
            ))
        }
        await client.disconnect()
    }

    func test_silentConsole_returnsEmptyResponse() async throws {
        // Some accepted commands print nothing; silence must not fail a push.
        let fixture = try Fixture { _ in nil }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        let response = try await client.send("Label Sequence 18 \"X\"")

        XCTAssertEqual(response, "")
        await client.disconnect()
    }

    /// #816 — `connect()` drains the greeting so it cannot be mistaken for the
    /// first command's response. It used to do that by sleeping one `settle`
    /// and clearing whatever had turned up, which is a bet that the banner beats
    /// the clock: on a loaded machine it does not, and the greeting then lands in
    /// the *next* harvest. That is what made this suite fail nondeterministically
    /// on a full local run while passing in isolation — the two tests that
    /// compare the response exactly were the ones that noticed.
    ///
    /// `bannerDelay` here is longer than `settle`, so the old timer-based drain
    /// fails this every time rather than once in a few hundred runs.
    func test_slowBanner_isNotHarvestedAsTheFirstResponse() async throws {
        let fixture = try Fixture(bannerDelay: 0.12) { _ in "Error #12 at line 1\r\n" }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        do {
            _ = try await client.send("Import \"x\" At 18 /nc")
            XCTFail("expected console failure")
        } catch let failure as MA2TelnetClient.Failure {
            XCTAssertEqual(failure, .console(
                command: "Import \"x\" At 18 /nc",
                response: "Error #12 at line 1"
            ))
        }
        await client.disconnect()
    }

    /// The same race with nothing to hide behind: a silent command has no
    /// response of its own, so a late banner becomes the response outright.
    func test_slowBanner_doesNotBecomeASilentCommandsResponse() async throws {
        let fixture = try Fixture(bannerDelay: 0.12) { _ in nil }
        defer { fixture.stop() }
        let client = client(port: fixture.port)
        try await client.connect()

        let response = try await client.send("Label Sequence 18 \"X\"")

        XCTAssertEqual(response, "")
        await client.disconnect()
    }

    func test_connectionRefused_throwsConnectionFailed() async {
        // Port 1 on loopback is never listening.
        let client = client(port: 1)
        do {
            try await client.connect()
            XCTFail("expected connectionFailed")
        } catch let failure as MA2TelnetClient.Failure {
            if case .connectionFailed = failure {
                // expected
            } else {
                XCTFail("unexpected failure \(failure)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
