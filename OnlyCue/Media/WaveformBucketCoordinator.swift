import Foundation

/// Coalesces waveform bucket production by cache key: concurrent subscribers for
/// the same key share ONE underlying `bucketStream`, so a background prewarm and
/// a foreground open of the same file never decode it twice (#733). Each
/// subscriber still receives the full progressive snapshot sequence, and a late
/// joiner is immediately replayed the latest snapshot so it never starts blank.
///
/// When the last subscriber for a key cancels, the shared producer is cancelled
/// and the session dropped.
actor WaveformBucketCoordinator {

    static let shared = WaveformBucketCoordinator()

    private struct Session {
        var latest: [WaveformBucket] = []
        var subscribers: [UUID: AsyncThrowingStream<[WaveformBucket], Error>.Continuation] = [:]
        var producer: Task<Void, Never>?
    }

    private var sessions: [String: Session] = [:]

    /// The coalescing key shared by the prewarmer and the foreground container so
    /// they attach to the SAME in-flight production (a drifting key would silently
    /// double-decode). Falls back to the URL when no content fingerprint is known.
    static func cacheKey(hash: String?, url: URL, bucketMillis: Int, excludingChannel: Int?) -> String {
        let base = hash ?? url.absoluteString
        let channel = excludingChannel.map(String.init) ?? "none"
        return "\(base)-\(bucketMillis)ms-xc\(channel)"
    }

    /// A progressive bucket stream for `key`. If a production for `key` is already
    /// in flight, this attaches to it (replaying the latest snapshot) instead of
    /// starting a second one; otherwise `produce` is invoked exactly once.
    nonisolated func stream(
        for key: String,
        produce: @escaping @Sendable () -> AsyncThrowingStream<[WaveformBucket], Error>
    ) -> AsyncThrowingStream<[WaveformBucket], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            Task { await self.subscribe(key: key, id: id, continuation: continuation, produce: produce) }
            continuation.onTermination = { _ in
                Task { await self.unsubscribe(key: key, id: id) }
            }
        }
    }

    private func subscribe(
        key: String,
        id: UUID,
        continuation: AsyncThrowingStream<[WaveformBucket], Error>.Continuation,
        produce: @escaping @Sendable () -> AsyncThrowingStream<[WaveformBucket], Error>
    ) {
        var session = sessions[key] ?? Session()
        if !session.latest.isEmpty { continuation.yield(session.latest) }
        session.subscribers[id] = continuation
        let needsProducer = session.producer == nil
        sessions[key] = session

        guard needsProducer else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await snapshot in produce() {
                    await self.broadcast(key: key, snapshot: snapshot)
                }
                await self.complete(key: key, failure: nil)
            } catch {
                await self.complete(key: key, failure: error)
            }
        }
        sessions[key]?.producer = task
    }

    private func broadcast(key: String, snapshot: [WaveformBucket]) {
        guard var session = sessions[key] else { return }
        session.latest = snapshot
        sessions[key] = session
        for continuation in session.subscribers.values {
            continuation.yield(snapshot)
        }
    }

    private func complete(key: String, failure: Error?) {
        guard let session = sessions[key] else { return }
        for continuation in session.subscribers.values {
            continuation.finish(throwing: failure)
        }
        sessions[key] = nil
    }

    private func unsubscribe(key: String, id: UUID) {
        guard var session = sessions[key] else { return }
        session.subscribers[id] = nil
        if session.subscribers.isEmpty {
            session.producer?.cancel()
            sessions[key] = nil
        } else {
            sessions[key] = session
        }
    }
}
