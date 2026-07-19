import Foundation
import Network

/// A discovered grandMA2 console (#686).
struct MA2Console: Equatable, Identifiable {
    let host: String
    let label: String?
    var id: String { host }
}

/// Discovers grandMA2 consoles by scanning each active interface's /24 for the
/// telnet port and keeping hosts whose banner looks like grandMA2 (#686).
/// Always user-initiated; never runs on its own.
enum MA2ConsoleScanner {

    /// grandMA2 telnet banner markers (the real onPC banner is the MA login art +
    /// "Please login !" + " [Channel]>").
    private static let markers = ["Please login", "[Channel]"]

    /// Orchestration: probe every host in each subnet's `.1…254`, de-duped.
    static func scan(
        subnets: [String],
        hosts: ClosedRange<Int> = 1...254,
        probe: @escaping @Sendable (String) async -> MA2Console?
    ) async -> [MA2Console] {
        var results: [MA2Console] = []
        await withTaskGroup(of: MA2Console?.self) { group in
            for subnet in subnets {
                for octet in hosts {
                    group.addTask { await probe("\(subnet).\(octet)") }
                }
            }
            for await found in group {
                if let found { results.append(found) }
            }
        }
        var seen = Set<String>()
        return results
            .filter { seen.insert($0.host).inserted }
            .sorted { $0.host < $1.host }
    }

    /// Connects to `host:port`, reads the banner, and returns a console iff the
    /// banner carries a grandMA2 marker.
    static func bannerProbe(
        _ host: String,
        port: UInt16 = 30000,
        connectTimeout: TimeInterval = 0.4,
        bannerWindow: TimeInterval = 0.5
    ) async -> MA2Console? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "OnlyCue.MA2ConsoleScanner")
        defer { connection.cancel() }

        guard await waitReady(connection, queue: queue, timeout: connectTimeout) else { return nil }
        let banner = await readBanner(connection, queue: queue, window: bannerWindow)
        return markers.contains(where: banner.contains) ? MA2Console(host: host, label: nil) : nil
    }

    private static func waitReady(
        _ connection: NWConnection,
        queue: DispatchQueue,
        timeout: TimeInterval
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let box = ResumeOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if box.take() { continuation.resume(returning: true) }
                case .failed, .waiting, .cancelled:
                    if box.take() { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if box.take() { continuation.resume(returning: false) }
            }
        }
    }

    private static func readBanner(
        _ connection: NWConnection,
        queue: DispatchQueue,
        window: TimeInterval
    ) async -> String {
        let data: Data = await withCheckedContinuation { continuation in
            let box = ResumeOnce()
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, _, _ in
                if box.take() { continuation.resume(returning: chunk ?? Data()) }
            }
            queue.asyncAfter(deadline: .now() + window) {
                if box.take() { continuation.resume(returning: Data()) }
            }
        }
        return String(bytes: data, encoding: .utf8)
            ?? String(bytes: data, encoding: .isoLatin1)
            ?? ""
    }

    /// Production scan: the local interface /24s, banner-probed, with the Mac's
    /// own interface IPs excluded from the results.
    static func scan() async -> [MA2Console] {
        let mine = Set(localInterfaceIPs())
        return await scan(subnets: localSubnets(), probe: { await bannerProbe($0) })
            .filter { !mine.contains($0.host) }
    }

    /// `"a.b.c"` /24 prefixes of up, non-loopback, non-point-to-point IPv4 interfaces.
    static func localSubnets() -> [String] {
        Set(localInterfaceIPs().compactMap { ip -> String? in
            let parts = ip.split(separator: ".")
            return parts.count == 4 ? parts.prefix(3).joined(separator: ".") : nil
        }).sorted()
    }

    /// IPv4 addresses of up, non-loopback, non-point-to-point interfaces.
    static func localInterfaceIPs() -> [String] {
        var addresses: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            if let ip = ipv4Address(of: current.pointee) { addresses.append(ip) }
        }
        return addresses
    }

    private static func ipv4Address(of interface: ifaddrs) -> String? {
        let flags = Int32(interface.ifa_flags)
        guard (flags & IFF_UP) != 0,
              (flags & IFF_LOOPBACK) == 0,
              (flags & IFF_POINTOPOINT) == 0,
              let sockaddr = interface.ifa_addr,
              sockaddr.pointee.sa_family == UInt8(AF_INET)
        else { return nil }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            sockaddr,
            socklen_t(sockaddr.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        return result == 0 ? String(cString: host) : nil
    }
}

/// One-shot resume guard for the scanner's continuations.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func take() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
