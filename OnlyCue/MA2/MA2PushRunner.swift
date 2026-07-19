import Foundation
import Observation

/// Transport seam for `MA2PushRunner` so tests mock the console session
/// (`MA2TelnetClient` is the production conformer).
protocol MA2PushTransport: Sendable {
    func connect() async throws
    func login(username: String, password: String) async throws
    @discardableResult
    func send(_ command: String) async throws -> String
    func disconnect() async
}

extension MA2TelnetClient: MA2PushTransport {}

/// Upload seam for `MA2PushRunner` (`MA2CurlUploader` in production).
protocol MA2Uploading: Sendable {
    func upload(xml: String, filename: String, host: String) async throws
}

struct MA2CurlUploader: MA2Uploading {
    func upload(xml: String, filename: String, host: String) async throws {
        try await MA2FTPUploader.upload(xml: xml, filename: filename, host: host)
    }
}

/// Executes a push plan (#683): FTP the two XML files, then run the telnet
/// commands one by one with per-step progress. Stops on the first error —
/// the push is idempotent, so re-pushing is the recovery path.
@MainActor
@Observable
final class MA2PushRunner {

    enum StepState: Equatable {
        case pending
        case running
        case done
        case failed(String)
    }

    struct Step: Identifiable, Equatable {
        let id: Int
        var title: String
        var state: StepState = .pending
    }

    private(set) var steps: [Step] = []
    private(set) var isRunning = false
    private(set) var didSucceed = false
    private(set) var failureMessage: String?

    init(transport: MA2PushTransport, uploader: MA2Uploading, interCommandDelay: TimeInterval) {
        fatalError("unimplemented")
    }

    func run(plan: MA2PushPlan, host: String, username: String, password: String) async {
        fatalError("unimplemented")
    }
}
