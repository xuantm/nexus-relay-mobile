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
        let id = candidate.id
        
        // discovered -> exporting
        try await ledger.markExporting(id: id)
        var batch = try await ledger.nextUploadBatch(limit: 10)
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
        let suffix = batch.first?.fingerprintSuffix ?? AssetFingerprinter.getFingerprintSuffix(fingerprint: AssetFingerprinter.generateFingerprint(candidate: candidate))
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
        let id = candidate.id
        
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
        let id = candidate.id
        
        // Non-retryable failure (e.g. invalid file format)
        try await ledger.markFailed(id: id, error: "File corrupted", retryable: false)
        let batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertTrue(batch.isEmpty) // Non-retryable fails immediately and is excluded
    }
}
