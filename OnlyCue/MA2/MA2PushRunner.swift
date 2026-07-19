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

    private let transport: MA2PushTransport
    private let uploader: MA2Uploading
    /// MA2's telnet remote drops lines fired back-to-back; ~0.3 s between
    /// commands is the rate the gma2 community tooling settled on.
    private let interCommandDelay: TimeInterval

    init(
        transport: MA2PushTransport,
        uploader: MA2Uploading = MA2CurlUploader(),
        interCommandDelay: TimeInterval = 0.3
    ) {
        self.transport = transport
        self.uploader = uploader
        self.interCommandDelay = interCommandDelay
    }

    func run(plan: MA2PushPlan, host: String, username: String, password: String) async {
        var titles = [
            "Upload \(plan.sequenceUpload.filename)",
            "Upload \(plan.timecodeUpload.filename)",
            "Connect to \(host)",
            "Login as \(username)"
        ]
        titles.append(contentsOf: plan.commands)
        steps = titles.enumerated().map { Step(id: $0.offset, title: $0.element) }
        isRunning = true
        didSucceed = false
        failureMessage = nil
        defer { isRunning = false }

        // Uploads first: if FTP is unavailable there is nothing to import and
        // the console is left untouched.
        guard await perform(step: 0, {
            try await self.uploader.upload(
                xml: plan.sequenceUpload.xml, filename: plan.sequenceUpload.filename, host: host
            )
        }) else { return }
        guard await perform(step: 1, {
            try await self.uploader.upload(
                xml: plan.timecodeUpload.xml, filename: plan.timecodeUpload.filename, host: host
            )
        }) else { return }

        guard await perform(step: 2, { try await self.transport.connect() }) else { return }
        guard await perform(step: 3, {
            try await self.transport.login(username: username, password: password)
        }) else {
            await transport.disconnect()
            return
        }

        for (offset, command) in plan.commands.enumerated() {
            let succeeded = await perform(step: 4 + offset) {
                try await self.transport.send(command)
                if self.interCommandDelay > 0 {
                    try await Task.sleep(for: .seconds(self.interCommandDelay))
                }
            }
            guard succeeded else {
                await transport.disconnect()
                return
            }
        }

        await transport.disconnect()
        didSucceed = true
    }

    /// Commands-only push (#683, Approach A): connect → login → run each command,
    /// no FTP uploads. Stops on the first error; idempotent, so re-push recovers.
    func run(commands: [String], host: String, username: String, password: String) async {
        var titles = ["Connect to \(host)", "Login as \(username)"]
        titles.append(contentsOf: commands)
        steps = titles.enumerated().map { Step(id: $0.offset, title: $0.element) }
        isRunning = true
        didSucceed = false
        failureMessage = nil
        defer { isRunning = false }

        guard await perform(step: 0, { try await self.transport.connect() }) else { return }
        guard await perform(step: 1, {
            try await self.transport.login(username: username, password: password)
        }) else {
            await transport.disconnect()
            return
        }

        for (offset, command) in commands.enumerated() {
            let succeeded = await perform(step: 2 + offset) {
                try await self.transport.send(command)
                if self.interCommandDelay > 0 {
                    try await Task.sleep(for: .seconds(self.interCommandDelay))
                }
            }
            guard succeeded else {
                await transport.disconnect()
                return
            }
        }

        await transport.disconnect()
        didSucceed = true
    }

    /// Runs one step, tracking `running` → `done` / `failed`. Returns whether
    /// to continue.
    private func perform(step index: Int, _ work: () async throws -> Void) async -> Bool {
        steps[index].state = .running
        do {
            try await work()
            steps[index].state = .done
            return true
        } catch {
            let message = Self.message(for: error)
            steps[index].state = .failed(message)
            failureMessage = message
            return false
        }
    }

    /// Human-readable text for the known failure shapes; the console's own
    /// error text is surfaced verbatim.
    private static func message(for error: Error) -> String {
        if error is CancellationError { return "Cancelled" }
        switch error {
        case let MA2TelnetClient.Failure.console(_, response):
            return response
        case let MA2TelnetClient.Failure.loginRejected(response):
            return response
        case let MA2TelnetClient.Failure.connectionFailed(text):
            return text
        case MA2TelnetClient.Failure.notConnected:
            return "Not connected"
        case let MA2FTPUploader.Failure.uploadFailed(_, text):
            return text
        default:
            return error.localizedDescription
        }
    }
}
