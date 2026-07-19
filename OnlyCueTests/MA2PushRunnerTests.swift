import XCTest
@testable import OnlyCue

/// #683 — the push executor: uploads the two XML files, then feeds the telnet
/// plan through the transport step by step, reporting per-step progress and
/// stopping on the first error (idempotent re-push is the recovery path).
@MainActor
final class MA2PushRunnerTests: XCTestCase {

    private final class MockTransport: MA2PushTransport, @unchecked Sendable {
        var log: [String] = []
        var failOnCommand: String?
        var failLogin = false
        var sendDelay: TimeInterval = 0

        func connect() async throws { log.append("connect") }
        func login(username: String, password: String) async throws {
            log.append("login \(username)")
            if failLogin { throw MA2TelnetClient.Failure.loginRejected(response: "no login") }
        }
        func send(_ command: String) async throws -> String {
            log.append(command)
            if sendDelay > 0 {
                try await Task.sleep(for: .seconds(sendDelay))
            }
            if command == failOnCommand {
                throw MA2TelnetClient.Failure.console(command: command, response: "Error #12")
            }
            return "OK"
        }
        func disconnect() async { log.append("disconnect") }
    }

    private final class MockUploader: MA2Uploading, @unchecked Sendable {
        var uploaded: [String] = []
        var failOnFilename: String?

        func upload(xml: String, filename: String, host: String) async throws {
            uploaded.append(filename)
            if filename == failOnFilename {
                throw MA2FTPUploader.Failure.uploadFailed(filename: filename, message: "530 Login denied")
            }
        }
    }

    private func plan() -> MA2PushPlan {
        MA2PushPlan(
            sequenceUpload: .init(filename: "onlycue_seq_18.xml", xml: "<seq/>"),
            timecodeUpload: .init(filename: "onlycue_tc_3.xml", xml: "<tc/>"),
            commands: ["Delete Sequence 18 /nc", "Import \"onlycue_seq_18\" At 18 /nc"]
        )
    }

    private func runner(
        transport: MockTransport,
        uploader: MockUploader
    ) -> MA2PushRunner {
        MA2PushRunner(transport: transport, uploader: uploader, interCommandDelay: 0)
    }

    func test_happyPath_runsUploadsThenTelnetPlan_inOrder() async {
        let transport = MockTransport()
        let uploader = MockUploader()
        let runner = runner(transport: transport, uploader: uploader)

        await runner.run(plan: plan(), host: "10.0.0.2", username: "admin", password: "pw")

        XCTAssertTrue(runner.didSucceed)
        XCTAssertNil(runner.failureMessage)
        XCTAssertEqual(uploader.uploaded, ["onlycue_seq_18.xml", "onlycue_tc_3.xml"])
        XCTAssertEqual(transport.log, [
            "connect",
            "login admin",
            "Delete Sequence 18 /nc",
            "Import \"onlycue_seq_18\" At 18 /nc",
            "disconnect"
        ])
        // One step per upload + connect + login + one per command, all done.
        XCTAssertEqual(runner.steps.count, 6)
        XCTAssertTrue(runner.steps.allSatisfy { $0.state == .done })
        XCTAssertFalse(runner.isRunning)
    }

    func test_consoleError_stopsRemainingCommands_andReportsText() async {
        let transport = MockTransport()
        transport.failOnCommand = "Delete Sequence 18 /nc"
        let uploader = MockUploader()
        let runner = runner(transport: transport, uploader: uploader)

        await runner.run(plan: plan(), host: "10.0.0.2", username: "admin", password: "pw")

        XCTAssertFalse(runner.didSucceed)
        XCTAssertEqual(runner.failureMessage, "Error #12")
        // The failing step is marked failed; the follow-up import never ran.
        XCTAssertFalse(transport.log.contains("Import \"onlycue_seq_18\" At 18 /nc"))
        XCTAssertEqual(transport.log.last, "disconnect")
        XCTAssertEqual(runner.steps[4].state, .failed("Error #12"))
        XCTAssertEqual(runner.steps[5].state, .pending)
    }

    func test_uploadFailure_neverTouchesTelnet() async {
        let transport = MockTransport()
        let uploader = MockUploader()
        uploader.failOnFilename = "onlycue_seq_18.xml"
        let runner = runner(transport: transport, uploader: uploader)

        await runner.run(plan: plan(), host: "10.0.0.2", username: "admin", password: "pw")

        XCTAssertFalse(runner.didSucceed)
        XCTAssertEqual(transport.log, [])
        XCTAssertEqual(uploader.uploaded, ["onlycue_seq_18.xml"])
        XCTAssertEqual(runner.steps[0].state, .failed("530 Login denied"))
    }

    func test_loginFailure_disconnects_andStops() async {
        let transport = MockTransport()
        transport.failLogin = true
        let uploader = MockUploader()
        let runner = runner(transport: transport, uploader: uploader)

        await runner.run(plan: plan(), host: "10.0.0.2", username: "admin", password: "bad")

        XCTAssertFalse(runner.didSucceed)
        XCTAssertEqual(transport.log, ["connect", "login admin", "disconnect"])
        XCTAssertEqual(runner.steps[3].state, .failed("no login"))
    }

    func test_cancellation_stopsRun_disconnects_andReportsCancelled() async {
        let transport = MockTransport()
        transport.sendDelay = 10 // park the run inside the first command
        let uploader = MockUploader()
        let runner = runner(transport: transport, uploader: uploader)

        let task = Task { await runner.run(plan: plan(), host: "10.0.0.2", username: "a", password: "p") }
        // Let the run reach the delayed send, then cancel it.
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value

        XCTAssertFalse(runner.didSucceed)
        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(runner.failureMessage, "Cancelled")
        XCTAssertEqual(transport.log.last, "disconnect")
    }
}
