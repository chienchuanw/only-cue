import Network
import XCTest
@testable import OnlyCue

/// #686 — console discovery: scan interface /24s for the telnet port and keep
/// hosts whose banner looks like grandMA2. Exercised against loopback banner
/// servers + an injected probe; no real network.
final class MA2ConsoleScannerTests: XCTestCase {

    /// Loopback TCP server that greets every connection with a fixed banner.
    private final class BannerServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "MA2ConsoleScannerTests.BannerServer")
        private var connections: [NWConnection] = []

        init(banner: String) throws {
            listener = try NWListener(using: .tcp, on: .any)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                connection.send(content: Data(banner.utf8), completion: .contentProcessed { _ in })
            }
            listener.start(queue: queue)
            XCTAssertEqual(ready.wait(timeout: .now() + 2), .success, "banner server never became ready")
        }

        var port: UInt16 { listener.port?.rawValue ?? 0 }

        func stop() {
            queue.sync {
                connections.forEach { $0.cancel() }
                connections.removeAll()
            }
            listener.cancel()
        }
    }

    func test_scan_collectsProbedConsoles_acrossSubnets_deduped() async {
        let probe: @Sendable (String) async -> MA2Console? = { host in
            host == "10.0.0.5" || host == "2.0.0.7" ? MA2Console(host: host, label: nil) : nil
        }

        let found = await MA2ConsoleScanner.scan(subnets: ["10.0.0", "2.0.0"], hosts: 1...10, probe: probe)

        XCTAssertEqual(Set(found.map(\.host)), ["10.0.0.5", "2.0.0.7"])
    }

    func test_bannerProbe_acceptsMaBanner() async throws {
        let server = try BannerServer(banner: "…MA art…\r\n [Channel]>Please login !\r\n")
        defer { server.stop() }

        let result = await MA2ConsoleScanner.bannerProbe("127.0.0.1", port: server.port)

        XCTAssertEqual(result, MA2Console(host: "127.0.0.1", label: nil))
    }

    func test_bannerProbe_rejectsNonMaBanner() async throws {
        let server = try BannerServer(banner: "220 vsFTPd 3.0 ready\r\n")
        defer { server.stop() }

        let result = await MA2ConsoleScanner.bannerProbe("127.0.0.1", port: server.port)

        XCTAssertNil(result)
    }
}
