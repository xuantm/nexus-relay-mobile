import XCTest
@testable import NexusRelayIPhone

final class UploadQueueViewModelTests: XCTestCase {
    func testQueueItemMapsStatusLabels() {
        let failed = UploadQueueItem(record: makeRecord(status: .failed, lastError: "Network error"))
        let uploading = UploadQueueItem(record: makeRecord(status: .uploading, lastError: nil))
        let waiting = UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil))

        XCTAssertEqual(failed.statusText, "Network error")
        XCTAssertEqual(uploading.statusText, "Uploading")
        XCTAssertEqual(waiting.statusText, "Waiting to upload")
    }

    func testQueueItemProgressFractions() {
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .uploaded, lastError: nil)).progressFraction, 1)
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .uploading, lastError: nil)).progressFraction, 0.72)
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil)).progressFraction, 0)
    }

    private func makeRecord(status: UploadStatus, lastError: String?) -> UploadLedgerRecord {
        UploadLedgerRecord(
            id: "record-1",
            assetLocalIdentifier: "asset-1",
            resourceKind: .image,
            fingerprintSuffix: "a3f91c0d8e74b210",
            originalFilename: "IMG_1234.HEIC",
            uploadedFileName: "IMG_1234__nr-a3f91c0d8e74b210.HEIC",
            mimeType: "image/heic",
            sizeBytes: 1024,
            status: status,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: nil,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: lastError
        )
    }
}
