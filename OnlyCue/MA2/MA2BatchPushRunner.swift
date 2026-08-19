import Foundation
import Observation

/// Executes a multi-song grandMA2 push over one console session (#765). Songs are pushed in
/// order; a per-song **console** error (a rejected command) marks that song failed and the
/// batch continues with the next — the push is idempotent (each song's plan deletes its slot
/// first), so a half-written slot is recovered by a re-push. A **connection/login** failure
/// is fatal: nothing can be pushed, so every song is marked failed.
@MainActor
@Observable
final class MA2BatchPushRunner {

    /// One song's pre-built command list (from `MA2CommandPlanner`, after auto-fill #763).
    struct SongCommands: Identifiable, Equatable {
        let itemID: MediaItem.ID
        let name: String
        let commands: [String]
        var id: MediaItem.ID { itemID }
    }

    enum SongState: Equatable {
        case pending
        case running
        case done
        case failed(String)
    }

    struct SongProgress: Identifiable, Equatable {
        let itemID: MediaItem.ID
        let name: String
        var state: SongState = .pending
        var id: MediaItem.ID { itemID }
    }

    private(set) var songs: [SongProgress] = []
    private(set) var isRunning = false
    /// Set when the whole batch aborts (connection/login failure).
    private(set) var fatalMessage: String?

    var succeededCount: Int { songs.filter { $0.state == .done }.count }
    var failedCount: Int { songs.filter { if case .failed = $0.state { return true } else { return false } }.count }
    var isComplete: Bool { !isRunning && !songs.isEmpty && songs.allSatisfy { $0.state != .pending && $0.state != .running } }

    private let transport: MA2PushTransport
    private let interCommandDelay: TimeInterval

    init(transport: MA2PushTransport, interCommandDelay: TimeInterval = 0.3) {
        self.transport = transport
        self.interCommandDelay = interCommandDelay
    }

    func run(songs input: [SongCommands], host: String, username: String, password: String) async {
        songs = input.map { SongProgress(itemID: $0.itemID, name: $0.name) }
        isRunning = true
        fatalMessage = nil
        defer { isRunning = false }

        do {
            try await transport.connect()
            try await transport.login(username: username, password: password)
        } catch {
            let message = Self.message(for: error)
            fatalMessage = message
            for index in songs.indices { songs[index].state = .failed(message) }
            await transport.disconnect()
            return
        }

        for (index, song) in input.enumerated() {
            songs[index].state = .running
            do {
                for command in song.commands {
                    try await send(command)
                }
                songs[index].state = .done
            } catch let error as MA2TelnetClient.Failure where Self.isFatal(error) {
                // The session is gone — fail this song and every remaining one.
                let message = Self.message(for: error)
                fatalMessage = message
                for remaining in index..<songs.count where songs[remaining].state != .done {
                    songs[remaining].state = .failed(message)
                }
                break
            } catch {
                // A rejected command (console error) — skip this song, keep the session.
                songs[index].state = .failed(Self.message(for: error))
            }
        }

        await transport.disconnect()
    }

    private func send(_ command: String) async throws {
        try await transport.send(command)
        if interCommandDelay > 0 {
            try await Task.sleep(for: .seconds(interCommandDelay))
        }
    }

    /// A dropped/failed session aborts the batch; a rejected command does not.
    private static func isFatal(_ failure: MA2TelnetClient.Failure) -> Bool {
        switch failure {
        case .connectionFailed, .notConnected, .loginRejected:
            return true
        case .console:
            return false
        }
    }

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
        default:
            return error.localizedDescription
        }
    }
}
