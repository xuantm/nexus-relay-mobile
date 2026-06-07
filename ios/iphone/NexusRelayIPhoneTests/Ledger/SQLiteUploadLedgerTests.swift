import XCTest
@testable import NexusRelayIPhone

final class SQLiteUploadLedgerTests: XCTestCase {
    private var tempDir: URL!
    private var dbURL: URL!
    private var ledger: SQLiteUploadLedger!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("test_ledger.sqlite")
        ledger = try! SQLiteUploadLedger(dbURL: dbURL)
    }

    override func tearDown() {
        ledger = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testUpsertAndNextBatch() async throws {
        let folderId = UUID()
        let candidate1 = PhotoAssetCandidate(
            assetLocalIdentifier: "asset1",
            resourceKind: .image,
            originalFilename: "photo1.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 1024
        )
        
        let candidate2 = PhotoAssetCandidate(
            assetLocalIdentifier: "asset2",
            resourceKind: .video,
            originalFilename: "video1.mp4",
            uniformTypeIdentifier: "public.mpeg-4",
            mimeType: "video/mp4",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 1920,
            pixelHeight: 1080,
            durationSeconds: 15.0,
            resourceFileSize: 20480
        )

        // 1. Upsert discovered
        try await ledger.upsertDiscovered([candidate1, candidate2], folderId: folderId)
        
        // 2. Fetch batch
        let batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.count, 2)
        XCTAssertTrue(batch.contains { $0.assetLocalIdentifier == "asset1" && $0.status == .discovered })
        XCTAssertTrue(batch.contains { $0.assetLocalIdentifier == "asset2" && $0.status == .discovered })
        
        // 3. Upsert duplicate candidate should update but not double rows
        try await ledger.upsertDiscovered([candidate1], folderId: folderId)
        let batchAfterDup = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batchAfterDup.count, 2)
    }

    func testLedgerTransitions() async throws {
        let folderId = UUID()
        let candidate = PhotoAssetCandidate(
            assetLocalIdentifier: "asset1",
            resourceKind: .image,
            originalFilename: "photo1.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 1024
        )

        try await ledger.upsertDiscovered([candidate], folderId: folderId)
        var batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.count, 1)
        let id = try XCTUnwrap(batch.first?.id)
        
        // discovered -> exporting
        try await ledger.markExporting(id: id)
        batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.status, .exporting)
        
        // exporting -> readyToUpload
        let fakeStagedURL = URL(string: "file:///tmp/staged/photo1.jpg")!
        try await ledger.markReady(id: id, stagedFileURL: fakeStagedURL, sizeBytes: 1024)
        batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.status, .readyToUpload)
        XCTAssertEqual(batch.first?.localStagedFileURL, fakeStagedURL)
        
        // readyToUpload -> uploading
        try await ledger.markUploading(id: id)
        batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.status, .uploading)
        
        // uploading -> uploaded
        let uploadId = UUID()
        try await ledger.markUploaded(id: id, backendUploadId: uploadId)
        batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertTrue(batch.isEmpty) // uploaded items are not in next upload batch
        
        // markSyncedByFingerprintSuffixes
        let fp = AssetFingerprinter.generateFingerprint(candidate: candidate)
        let suffix = AssetFingerprinter.getFingerprintSuffix(fingerprint: fp)
        try await ledger.markSyncedByFingerprintSuffixes([suffix], folderId: folderId)
        
        // Verify synced items are no longer fetched for upload.
        batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertTrue(batch.isEmpty)
    }

    func testFailedRetries() async throws {
        let folderId = UUID()
        let candidate = PhotoAssetCandidate(
            assetLocalIdentifier: "asset1",
            resourceKind: .image,
            originalFilename: "photo1.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 1024
        )

        try await ledger.upsertDiscovered([candidate], folderId: folderId)
        let batchForId = try await ledger.nextUploadBatch(limit: 10)
        let id = try XCTUnwrap(batchForId.first?.id)
        
        // First retryable failure
        try await ledger.markFailed(id: id, error: "Network timed out", retryable: true)
        var batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.status, .failed)
        XCTAssertEqual(batch.first?.attemptCount, 1)
        XCTAssertEqual(batch.first?.lastError, "Network timed out")
        
        // Second retryable failure
        try await ledger.markFailed(id: id, error: "HTTP 500", retryable: true)
        batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.first?.attemptCount, 2)
        
        // Third retryable failure -> reaches limit (attemptCount = 3)
        try await ledger.markFailed(id: id, error: "HTTP 502", retryable: true)
        batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertTrue(batch.isEmpty) // hit max retries, excluded
    }
    
    func testFailedNonRetryable() async throws {
        let folderId = UUID()
        let candidate = PhotoAssetCandidate(
            assetLocalIdentifier: "asset1",
            resourceKind: .image,
            originalFilename: "photo1.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 1024
        )

        try await ledger.upsertDiscovered([candidate], folderId: folderId)
        let batchForId = try await ledger.nextUploadBatch(limit: 10)
        let id = try XCTUnwrap(batchForId.first?.id)
        
        // Non-retryable failure (e.g. invalid file format)
        try await ledger.markFailed(id: id, error: "File corrupted", retryable: false)
        let batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertTrue(batch.isEmpty) // Non-retryable fails immediately and is excluded
    }

    func testListQueueRecordsFiltersActiveWaitingAndFailed() async throws {
        let folderId = UUID()
        let candidate1 = makeCandidate(assetId: "asset-active", fileName: "active.jpg")
        let candidate2 = makeCandidate(assetId: "asset-waiting", fileName: "waiting.jpg")
        let candidate3 = makeCandidate(assetId: "asset-failed", fileName: "failed.jpg")

        try await ledger.upsertDiscovered([candidate1, candidate2, candidate3], folderId: folderId)
        
        let allDiscovered = try await ledger.listQueueRecords(filter: .all, limit: 10)
        guard let idActive = allDiscovered.first(where: { $0.assetLocalIdentifier == "asset-active" })?.id,
              let idFailed = allDiscovered.first(where: { $0.assetLocalIdentifier == "asset-failed" })?.id else {
            XCTFail("Failed to find inserted record IDs")
            return
        }
        
        try await ledger.markUploading(id: idActive)
        try await ledger.markFailed(id: idFailed, error: "Network error", retryable: true)

        let all = try await ledger.listQueueRecords(filter: .all, limit: 10)
        let active = try await ledger.listQueueRecords(filter: .active, limit: 10)
        let failed = try await ledger.listQueueRecords(filter: .failed, limit: 10)

        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(active.map(\.assetLocalIdentifier), ["asset-active"])
        XCTAssertEqual(failed.map(\.assetLocalIdentifier), ["asset-failed"])
    }

    func testRetryFailedResetsAttemptsAndClearsError() async throws {
        let folderId = UUID()
        let candidate = makeCandidate(assetId: "asset-failed", fileName: "failed.jpg")

        try await ledger.upsertDiscovered([candidate], folderId: folderId)
        let batch = try await ledger.listQueueRecords(filter: .all, limit: 10)
        let id = try XCTUnwrap(batch.first?.id)
        try await ledger.markFailed(id: id, error: "Server unavailable", retryable: false)
        try await ledger.retryFailed(ids: [id])

        let records = try await ledger.listQueueRecords(filter: .all, limit: 10)
        XCTAssertEqual(records.first?.status, .discovered)
        XCTAssertEqual(records.first?.attemptCount, 0)
        XCTAssertNil(records.first?.lastError)
    }

    private func makeCandidate(assetId: String, fileName: String) -> PhotoAssetCandidate {
        PhotoAssetCandidate(
            assetLocalIdentifier: assetId,
            resourceKind: .image,
            originalFilename: fileName,
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(timeIntervalSince1970: 1_780_000_000),
            modificationDate: nil,
            pixelWidth: 1200,
            pixelHeight: 800,
            durationSeconds: nil,
            resourceFileSize: 1024
        )
    }
}

