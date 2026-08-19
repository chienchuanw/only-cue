import XCTest
@testable import OnlyCue

/// #765 — the batch runner pushes each song over one console session, and on a per-song
/// console error it skips that song and continues, ending with a per-song summary. A
/// connection/login failure is fatal (nothing can be pushed).
@MainActor
final class MA2BatchPushRunnerTests: XCTestCase {

    /// Programmable transport: throws `.console` for any command containing a song's fail
    /// marker; optionally fails connect. Records every command actually sent.
    private final class FakeTransport: MA2PushTransport, @unchecked Sendable {
        var sent: [String] = []
        var failConnect = false
        var failCommandsContaining: String?

        func connect() async throws {
            if failConnect { throw MA2TelnetClient.Failure.connectionFailed("refused") }
        }
        func login(username: String, password: String) async throws {}
        @discardableResult
        func send(_ command: String) async throws -> String {
            sent.append(command)
            if let marker = failCommandsContaining, command.contains(marker) {
                throw MA2TelnetClient.Failure.console(command: command, response: "Error #201")
            }
            return ""
        }
        func disconnect() async {}
    }

    private func song(_ name: String, commands: [String]) -> MA2BatchPushRunner.SongCommands {
        MA2BatchPushRunner.SongCommands(itemID: UUID(), name: name, commands: commands)
    }

    private func run(_ transport: FakeTransport, _ songs: [MA2BatchPushRunner.SongCommands]) async -> MA2BatchPushRunner {
        let runner = MA2BatchPushRunner(transport: transport, interCommandDelay: 0)
        await runner.run(songs: songs, host: "h", username: "u", password: "p")
        return runner
    }

    func test_allSongsSucceed_allDone() async {
        let transport = FakeTransport()
        let runner = await run(transport, [
            song("A", commands: ["Store A"]),
            song("B", commands: ["Store B"])
        ])
        XCTAssertEqual(runner.songs.map(\.state), [.done, .done])
        XCTAssertEqual(runner.succeededCount, 2)
        XCTAssertEqual(runner.failedCount, 0)
    }

    func test_oneSongConsoleError_isSkipped_othersContinue() async {
        let transport = FakeTransport()
        transport.failCommandsContaining = "BOOM"
        let runner = await run(transport, [
            song("A", commands: ["Store A"]),
            song("B", commands: ["Store BOOM"]),
            song("C", commands: ["Store C"])
        ])
        XCTAssertEqual(runner.songs[0].state, .done)
        if case .failed = runner.songs[1].state {} else { XCTFail("B should have failed") }
        XCTAssertEqual(runner.songs[2].state, .done, "C must still be pushed after B failed")
        XCTAssertEqual(runner.succeededCount, 2)
        XCTAssertEqual(runner.failedCount, 1)
        // C's command was still sent — the batch did not abort.
        XCTAssertTrue(transport.sent.contains("Store C"))
    }

    func test_connectionFailure_failsAllSongs() async {
        let transport = FakeTransport()
        transport.failConnect = true
        let runner = await run(transport, [song("A", commands: ["Store A"]), song("B", commands: ["Store B"])])
        XCTAssertEqual(runner.succeededCount, 0)
        XCTAssertEqual(runner.failedCount, 2)
        XCTAssertNotNil(runner.fatalMessage)
    }
}
