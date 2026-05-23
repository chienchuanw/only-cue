import AVFoundation
import Combine
import XCTest
@testable import OnlyCue

@MainActor
final class PlayerEngineEndOfMediaTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []
    private var fixtureURLs: [URL] = []

    override func tearDown() {
        cancellables.removeAll()
        for url in fixtureURLs {
            try? FileManager.default.removeItem(at: url)
        }
        fixtureURLs.removeAll()
        super.tearDown()
    }

    private func makeAsset() throws -> AVURLAsset {
        let url = try SilentAudioFixture.makeWAV(duration: 1)
        fixtureURLs.append(url)
        return AVURLAsset(url: url)
    }

    func test_publishesWhenAVPlayerItemEndsNaturally() async throws {
        let engine = PlayerEngine()
        await engine.load(asset: try makeAsset())

        let received = expectation(description: "mediaDidReachEnd fires")
        engine.mediaDidReachEnd
            .sink { received.fulfill() }
            .store(in: &cancellables)

        guard let item = engine.player.currentItem else {
            return XCTFail("expected a loaded AVPlayerItem")
        }
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )

        await fulfillment(of: [received], timeout: 1)
    }

    func test_doesNotPublishForADifferentItem() async throws {
        let engine = PlayerEngine()
        await engine.load(asset: try makeAsset())

        var fired = false
        engine.mediaDidReachEnd
            .sink { fired = true }
            .store(in: &cancellables)

        let strangerItem = AVPlayerItem(asset: try makeAsset())
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: strangerItem
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(fired)
    }

    func test_resubscribesAfterReload() async throws {
        let engine = PlayerEngine()
        await engine.load(asset: try makeAsset())
        await engine.load(asset: try makeAsset())

        let received = expectation(description: "fires for the second item")
        engine.mediaDidReachEnd
            .sink { received.fulfill() }
            .store(in: &cancellables)

        guard let item = engine.player.currentItem else {
            return XCTFail("expected a loaded AVPlayerItem")
        }
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )

        await fulfillment(of: [received], timeout: 1)
    }
}
