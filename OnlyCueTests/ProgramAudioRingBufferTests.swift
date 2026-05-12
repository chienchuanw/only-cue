import XCTest
@testable import OnlyCue

final class ProgramAudioRingBufferTests: XCTestCase {

    func test_pushThenDrain_returnsFramesInOrder() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 8)
        ring.push(interleavedStereo: [1, 10, 2, 20, 3, 30])   // 3 frames
        XCTAssertEqual(ring.drain(frameCount: 3), [1, 10, 2, 20, 3, 30])
    }

    func test_drain_moreThanAvailable_zeroFillsTail() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 8)
        ring.push(interleavedStereo: [1, 1, 2, 2])            // 2 frames
        XCTAssertEqual(ring.drain(frameCount: 4), [1, 1, 2, 2, 0, 0, 0, 0])
    }

    func test_drain_emptyBuffer_isAllZeros() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        XCTAssertEqual(ring.drain(frameCount: 3), [Float](repeating: 0, count: 6))
    }

    func test_drain_zeroFrames_isEmpty() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [1, 1])
        XCTAssertEqual(ring.drain(frameCount: 0), [])
    }

    func test_wrapAround_preservesOrder() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [1, 1, 2, 2, 3, 3])      // 3 frames
        _ = ring.drain(frameCount: 2)                         // consume frames 1,2
        ring.push(interleavedStereo: [4, 4, 5, 5])            // wraps
        XCTAssertEqual(ring.drain(frameCount: 3), [3, 3, 4, 4, 5, 5])
    }

    func test_push_overCapacity_dropsOldestFrames() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 3)
        ring.push(interleavedStereo: [1, 1, 2, 2, 3, 3])      // fills exactly
        ring.push(interleavedStereo: [4, 4, 5, 5])            // overflow by 2 → drop frames 1,2
        XCTAssertEqual(ring.drain(frameCount: 3), [3, 3, 4, 4, 5, 5])
    }

    func test_push_largerThanCapacity_keepsNewestFrames() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 2)
        ring.push(interleavedStereo: [1, 1, 2, 2, 3, 3, 4, 4]) // 4 frames into cap-2 → keep 3,4
        XCTAssertEqual(ring.drain(frameCount: 2), [3, 3, 4, 4])
    }

    func test_flush_discardsEverything() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [1, 1, 2, 2])
        ring.flush()
        XCTAssertEqual(ring.drain(frameCount: 2), [0, 0, 0, 0])
    }

    func test_oddSampleCount_isIgnored() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [1, 1, 2])  // 2.5 frames — rejected wholesale
        XCTAssertEqual(ring.drain(frameCount: 1), [0, 0])
    }

    func test_emptyPush_isNoOp() {
        let ring = ProgramAudioRingBuffer(capacityFrames: 4)
        ring.push(interleavedStereo: [])
        XCTAssertEqual(ring.drain(frameCount: 1), [0, 0])
    }
}
