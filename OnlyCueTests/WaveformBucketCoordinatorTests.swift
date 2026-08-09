import XCTest
@testable import OnlyCue

/// #733: the coordinator coalesces concurrent requests for the same cache key
/// into ONE underlying production (so a prewarm and a foreground open of the
/// same file never decode it twice), while each subscriber still receives the
/// progressive snapshot stream.
final class WaveformBucketCoordinatorTests: XCTestCase {

    /// Two subscribers to the same key that overlap in time must trigger the
    /// producer exactly once and both receive the full snapshot sequence.
    func test_concurrentSameKey_producesOnce() async throws {
        let coordinator = WaveformBucketCoordinator()
        let calls = CallCounter()

        async let first = drain(coordinator.stream(for: "same", produce: slowProduce(calls)))
        async let second = drain(coordinator.stream(for: "same", produce: slowProduce(calls)))
        let (firstResult, secondResult) = try await (first, second)

        XCTAssertEqual(calls.count, 1, "one shared production, not one per subscriber")
        XCTAssertEqual(firstResult.count, 5, "subscriber A receives the full sequence")
        XCTAssertEqual(secondResult.count, 5, "subscriber B receives the full sequence")
    }

    /// Distinct keys are independent — each gets its own production.
    func test_differentKeys_produceSeparately() async throws {
        let coordinator = WaveformBucketCoordinator()
        let calls = CallCounter()

        async let one = drain(coordinator.stream(for: "k1", produce: slowProduce(calls)))
        async let two = drain(coordinator.stream(for: "k2", produce: slowProduce(calls)))
        _ = try await (one, two)

        XCTAssertEqual(calls.count, 2, "each distinct key produces independently")
    }

    // MARK: - Helpers

    /// A producer that bumps `calls` once per invocation and yields five growing
    /// snapshots with small gaps, so two subscribers reliably overlap in flight.
    private func slowProduce(_ calls: CallCounter) -> @Sendable () -> AsyncThrowingStream<[WaveformBucket], Error> {
        { [calls] in
            calls.bump()
            return AsyncThrowingStream { continuation in
                Task {
                    var accumulated: [WaveformBucket] = []
                    for _ in 0..<5 {
                        try? await Task.sleep(nanoseconds: 30_000_000)
                        accumulated.append(WaveformBucket(peak: 1, rms: 1))
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                }
            }
        }
    }

    private func drain(_ stream: AsyncThrowingStream<[WaveformBucket], Error>) async throws -> [WaveformBucket] {
        var last: [WaveformBucket] = []
        for try await snapshot in stream { last = snapshot }
        return last
    }
}

/// Thread-safe call counter for asserting how many times a `@Sendable` closure ran.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
