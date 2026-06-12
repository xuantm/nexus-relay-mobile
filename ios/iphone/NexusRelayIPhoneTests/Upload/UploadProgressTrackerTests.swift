import XCTest
@testable import NexusRelayIPhone

final class UploadProgressTrackerTests: XCTestCase {
    func testRecordsRollingSpeedAndActiveBytes() async {
        let tracker = UploadProgressTracker()

        await tracker.resetSession()
        await tracker.recordUploadProgress(recordId: "a", bytesSent: 100, totalBytes: 1_000, at: Date(timeIntervalSince1970: 10))
        await tracker.recordUploadProgress(recordId: "a", bytesSent: 700, totalBytes: 1_000, at: Date(timeIntervalSince1970: 13))

        let snapshot = await tracker.snapshot(remainingBytes: 3_000)

        XCTAssertEqual(snapshot.activeUploadedBytes, 700)
        XCTAssertEqual(snapshot.activeTotalBytes, 1_000)
        XCTAssertEqual(snapshot.bytesPerSecond ?? 0, 200, accuracy: 0.1)
        XCTAssertEqual(snapshot.estimatedSecondsRemaining ?? 0, 15, accuracy: 0.1)
    }

    func testResetClearsSessionState() async {
        let tracker = UploadProgressTracker()

        await tracker.recordUploadProgress(recordId: "a", bytesSent: 250, totalBytes: 500, at: Date(timeIntervalSince1970: 1))
        await tracker.resetSession()
        let snapshot = await tracker.snapshot(remainingBytes: 500)

        XCTAssertEqual(snapshot.activeUploadedBytes, 0)
        XCTAssertEqual(snapshot.activeTotalBytes, 0)
        XCTAssertNil(snapshot.bytesPerSecond)
        XCTAssertNil(snapshot.estimatedSecondsRemaining)
    }
}
