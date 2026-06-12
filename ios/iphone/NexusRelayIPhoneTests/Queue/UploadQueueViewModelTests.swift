import XCTest
@testable import NexusRelayIPhone

final class UploadQueueViewModelTests: XCTestCase {
    func testQueueItemMapsStatusLabels() {
        let failed = UploadQueueItem(record: makeRecord(status: .failed, lastError: "Failed to get current user"))
        let uploading = UploadQueueItem(record: makeRecord(status: .uploading, lastError: nil))
        let waiting = UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil))

        XCTAssertEqual(failed.statusText, "Failed")
        XCTAssertEqual(uploading.statusText, "Uploading")
        XCTAssertEqual(waiting.statusText, "Pending")
        XCTAssertEqual(uploading.status, .Uploading)
        XCTAssertEqual(waiting.status, .Pending)
    }

    func testQueueItemProgressFractions() {
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .uploaded, lastError: nil)).progressFraction, 1)
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .uploading, lastError: nil)).progressFraction, 0.72)
        XCTAssertEqual(UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil)).progressFraction, 0)
    }

    func testQueueItemUploadModeTextUsesRouteDisplayName() {
        XCTAssertEqual(
            UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil, sizeBytes: 5 * 1024 * 1024)).uploadModeText,
            "Direct multipart upload"
        )
        XCTAssertEqual(
            UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil, sizeBytes: (5 * 1024 * 1024) + 1)).uploadModeText,
            "Direct resumable upload"
        )
        XCTAssertEqual(
            UploadQueueItem(record: makeRecord(status: .discovered, lastError: nil, sizeBytes: (90 * 1024 * 1024) + 1)).uploadModeText,
            "Chunked upload"
        )
    }

    private func makeRecord(status: UploadLedgerStatus, lastError: String?, sizeBytes: Int64 = 1024) -> UploadLedgerRecord {
        UploadLedgerRecord(
            id: "record-1",
            assetLocalIdentifier: "asset-1",
            resourceKind: .image,
            fingerprintSuffix: "a3f91c0d8e74b210",
            originalFilename: "IMG_1234.HEIC",
            uploadedFileName: "IMG_1234__nr-a3f91c0d8e74b210.HEIC",
            mimeType: "image/heic",
            sizeBytes: sizeBytes,
            status: status,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: nil,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: lastError
        )
    }

    @MainActor
    func testQueueViewModelLoadsFilteredRows() async throws {
        let ledger = FakeQueueLedger(records: [
            makeRecord(id: "1", status: .uploading),
            makeRecord(id: "2", status: .failed),
            makeRecord(id: "3", status: .discovered)
        ])
        let viewModel = UploadQueueViewModel(ledger: ledger)

        viewModel.selectedSegment = .failed
        await viewModel.load()

        XCTAssertEqual(viewModel.items.map(\.id), ["2"])
    }

    @MainActor
    func testRetryAllRetriesFailedIdsAndReloads() async throws {
        let ledger = FakeQueueLedger(records: [
            makeRecord(id: "1", status: .failed),
            makeRecord(id: "2", status: .failed)
        ])
        let viewModel = UploadQueueViewModel(ledger: ledger)

        await viewModel.load()
        await viewModel.retryAll()

        XCTAssertEqual(ledger.retriedIds, ["1", "2"])
    }

    @MainActor
    func testRetryRetriesSingleFailedId() async throws {
        let ledger = FakeQueueLedger(records: [
            makeRecord(id: "1", status: .failed),
            makeRecord(id: "2", status: .failed)
        ])
        let viewModel = UploadQueueViewModel(ledger: ledger)

        await viewModel.load()
        await viewModel.retry(id: "2")

        XCTAssertEqual(ledger.retriedIds, ["2"])
    }

    @MainActor
    func testLoadCoalescesConcurrentSegmentChangeToLatestRows() async throws {
        let ledger = FakeQueueLedger(records: [
            makeRecord(id: "1", status: .uploading),
            makeRecord(id: "2", status: .failed)
        ])
        ledger.delayNanoseconds = 200_000_000
        let viewModel = UploadQueueViewModel(ledger: ledger)

        let firstLoad = Task { await viewModel.load() }
        while !viewModel.isLoading {
            await Task.yield()
        }
        viewModel.selectedSegment = .failed
        await viewModel.load()
        await firstLoad.value

        XCTAssertEqual(ledger.listCallCount, 2)
        XCTAssertEqual(ledger.requestedFilters, [.all, .failed])
        XCTAssertEqual(viewModel.items.map(\.id), ["2"])
    }

    private func makeRecord(id: String, status: UploadLedgerStatus) -> UploadLedgerRecord {
        UploadLedgerRecord(
            id: id,
            assetLocalIdentifier: "asset-\(id)",
            resourceKind: .image,
            fingerprintSuffix: "a3f91c0d8e74b210",
            originalFilename: "IMG_\(id).HEIC",
            uploadedFileName: "IMG_\(id)__nr-a3f91c0d8e74b210.HEIC",
            mimeType: "image/heic",
            sizeBytes: 1024,
            status: status,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: nil,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: status == .failed ? "Upload failed" : nil
        )
    }
}

final class FakeQueueLedger: UploadLedger {
    private let lock = NSLock()
    var records: [UploadLedgerRecord]
    var retriedIds: [String] = []
    private var _listCallCount = 0
    private var _requestedFilters: [UploadQueueFilter] = []
    var delayNanoseconds: UInt64 = 0

    var listCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _listCallCount
    }
    var requestedFilters: [UploadQueueFilter] {
        lock.lock()
        defer { lock.unlock() }
        return _requestedFilters
    }

    init(records: [UploadLedgerRecord]) {
        self.records = records
    }

    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] {
        lock.lock()
        _listCallCount += 1
        _requestedFilters.append(filter)
        lock.unlock()
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        switch filter {
        case .all: return records
        case .active: return records.filter { $0.status == .uploading || $0.status == .exporting }
        case .failed: return records.filter { $0.status == .failed }
        }
    }

    func retryFailed(ids: [String]) async throws {
        retriedIds = ids
    }

    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws {}
    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord] { [] }
    func markExporting(id: String) async throws {}
    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws {}
    func markUploading(id: String) async throws {}
    func markUploaded(id: String, backendUploadId: UUID) async throws {}
    func markSyncedByUploadedFileNames(_ fileNames: Set<String>, folderId: UUID) async throws {}
    func markFailed(id: String, error: String, retryable: Bool) async throws {}
    func getLedgerCounts() async throws -> LedgerCounts {
        LedgerCounts(queued: 0, uploaded: 0, failed: 0, exporting: 0, uploading: 0)
    }
}
