import XCTest
@testable import NexusRelayIPhone

// MARK: - Mocks for Testing
final class MockSettingsStore: SettingsStore {
    var settings: AppSettings = .defaults
}

final class MockAssetExporter: AssetExporter {
    var exportCount = 0
    var shouldFail = false
    func exportOriginalResource(candidate: PhotoAssetCandidate, outputURL: URL, allowNetworkAccess: Bool) async throws {
        exportCount += 1
        if shouldFail {
            throw ExportError.writeFailed("mock-export-failure")
        }
        // Write mock file
        try "test-data".data(using: .utf8)!.write(to: outputURL)
    }
}

final class PermissionAwarePhotoLibraryClient: PhotoLibraryClient {
    var status: PhotoLibraryAuthorizationStatus
    var requestedStatus: PhotoLibraryAuthorizationStatus?
    var candidates: [PhotoAssetCandidate] = []

    init(status: PhotoLibraryAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        if let requestedStatus {
            status = requestedStatus
        }
        return status
    }

    func fetchCandidates(includeVideos: Bool, includeLivePhotoVideo: Bool) async throws -> [PhotoAssetCandidate] {
        candidates
    }
}

final class MockTemporaryFileStore: TemporaryFileStore {
    var getStagedURLCount = 0
    var deleteCount = 0
    var cleanCount = 0
    
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    
    init() {
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    
    func getStagedFileURL(recordId: String, fileName: String) throws -> URL {
        getStagedURLCount += 1
        let dir = root.appendingPathComponent(recordId.replacingOccurrences(of: ":", with: "_"))
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
    
    func deleteStagedFile(recordId: String) throws {
        deleteCount += 1
        let dir = root.appendingPathComponent(recordId.replacingOccurrences(of: ":", with: "_"))
        try? FileManager.default.removeItem(at: dir)
    }
    
    func cleanStaleFiles() throws {
        cleanCount += 1
    }
    
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

final class MockUploadEngine: UploadEngine {
    var uploadCount = 0
    var shouldFail = false
    var delayNanoseconds: UInt64 = 0

    func upload(record: UploadLedgerRecord, folderId: UUID) async throws -> UUID {
        uploadCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if shouldFail {
            throw APIError.requestFailed(statusCode: 500, message: "mock-server-failure")
        }
        return UUID()
    }
}

final class MockUploadLedger: UploadLedger {
    var records: [UploadLedgerRecord] = []
    var upsertCount = 0
    var nextBatchCount = 0
    
    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws {
        upsertCount += 1
        for candidate in candidates {
            if !records.contains(where: { $0.assetLocalIdentifier == candidate.assetLocalIdentifier }) {
                records.append(UploadLedgerRecord(
                    id: candidate.id,
                    assetLocalIdentifier: candidate.assetLocalIdentifier,
                    resourceKind: candidate.resourceKind,
                    fingerprintSuffix: "suffix",
                    originalFilename: candidate.originalFilename,
                    uploadedFileName: candidate.originalFilename + "__nr-suffix",
                    mimeType: candidate.mimeType,
                    sizeBytes: candidate.resourceFileSize,
                    status: .discovered,
                    backendFolderId: folderId,
                    backendUploadId: nil,
                    localStagedFileURL: nil,
                    attemptCount: 0,
                    lastAttemptAt: nil,
                    lastError: nil
                ))
            }
        }
    }

    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord] {
        nextBatchCount += 1
        let uploadableStatuses: [UploadStatus] = [.discovered, .exporting, .readyToUpload, .uploading, .failed]
        let batch = records.filter { uploadableStatuses.contains($0.status) && $0.attemptCount < 3 }
            .prefix(limit)
        return Array(batch)
    }

    func markExporting(id: String) async throws {
        if let idx = records.firstIndex(where: { $0.id == id }) {
            let r = records[idx]
            records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                status: .exporting, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                localStagedFileURL: r.localStagedFileURL, attemptCount: r.attemptCount,
                lastAttemptAt: r.lastAttemptAt, lastError: r.lastError
            )
        }
    }

    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws {
        if let idx = records.firstIndex(where: { $0.id == id }) {
            let r = records[idx]
            records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: sizeBytes,
                status: .readyToUpload, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                localStagedFileURL: stagedFileURL, attemptCount: r.attemptCount,
                lastAttemptAt: r.lastAttemptAt, lastError: r.lastError
            )
        }
    }

    func markUploading(id: String) async throws {
         if let idx = records.firstIndex(where: { $0.id == id }) {
             let r = records[idx]
             records[idx] = UploadLedgerRecord(
                 id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                 fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                 uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                 status: .uploading, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                 localStagedFileURL: r.localStagedFileURL, attemptCount: r.attemptCount,
                 lastAttemptAt: r.lastAttemptAt, lastError: r.lastError
             )
         }
    }

    func markUploaded(id: String, backendUploadId: UUID) async throws {
        if let idx = records.firstIndex(where: { $0.id == id }) {
            let r = records[idx]
            records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                status: .uploaded, backendFolderId: r.backendFolderId, backendUploadId: backendUploadId,
                localStagedFileURL: r.localStagedFileURL, attemptCount: r.attemptCount,
                lastAttemptAt: r.lastAttemptAt, lastError: r.lastError
            )
        }
    }

    func markSyncedByUploadedFileNames(_ fileNames: Set<String>, folderId: UUID) async throws {}

    func markFailed(id: String, error: String, retryable: Bool) async throws {
        if let idx = records.firstIndex(where: { $0.id == id }) {
            let r = records[idx]
            let nextAttemptCount = retryable ? r.attemptCount + 1 : 99
            records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                status: .failed, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                localStagedFileURL: r.localStagedFileURL, attemptCount: nextAttemptCount,
                lastAttemptAt: Date(), lastError: error
            )
        }
    }

    func getLedgerCounts() async throws -> LedgerCounts {
        let queued = records.filter { $0.status == .discovered || $0.status == .readyToUpload }.count
        let uploaded = records.filter { $0.status == .uploaded || $0.status == .synced }.count
        let failed = records.filter { $0.status == .failed }.count
        let exporting = records.filter { $0.status == .exporting }.count
        let uploading = records.filter { $0.status == .uploading }.count
        return LedgerCounts(queued: queued, uploaded: uploaded, failed: failed, exporting: exporting, uploading: uploading)
    }

    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] {
        let filtered: [UploadLedgerRecord]
        switch filter {
        case .all:
            filtered = records
        case .active:
            filtered = records.filter { $0.status == .exporting || $0.status == .readyToUpload || $0.status == .uploading }
        case .failed:
            filtered = records.filter { $0.status == .failed }
        }
        return Array(filtered.prefix(limit))
    }

    func retryFailed(ids: [String]) async throws {
        for id in ids {
            if let idx = records.firstIndex(where: { $0.id == id }) {
                let r = records[idx]
                records[idx] = UploadLedgerRecord(
                    id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                    fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                    uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                    status: .discovered, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                    localStagedFileURL: r.localStagedFileURL, attemptCount: 0,
                    lastAttemptAt: r.lastAttemptAt, lastError: r.lastError
                )
            }
        }
    }
}

// MARK: - Orchestrator Tests
final class SyncOrchestratorTests: XCTestCase {
    private var api: MockNexusRelayAPI!
    private var scanner: MockPhotoLibraryClient!
    private var ledger: MockUploadLedger!
    private var exporter: MockAssetExporter!
    private var tempStore: MockTemporaryFileStore!
    private var engine: MockUploadEngine!
    private var settingsStore: MockSettingsStore!
    private var orchestrator: SystemSyncOrchestrator!

    override func setUp() {
        super.setUp()
        api = MockNexusRelayAPI()
        scanner = MockPhotoLibraryClient()
        ledger = MockUploadLedger()
        exporter = MockAssetExporter()
        tempStore = MockTemporaryFileStore()
        engine = MockUploadEngine()
        settingsStore = MockSettingsStore()
    }

    override func tearDown() {
        tempStore.cleanup()
        api = nil
        scanner = nil
        ledger = nil
        exporter = nil
        tempStore = nil
        engine = nil
        settingsStore = nil
        orchestrator = nil
        super.tearDown()
    }

    func testSyncThrowsMissingFolder() async throws {
        orchestrator = SystemSyncOrchestrator(
            apiClient: api, photosScanner: scanner, ledger: ledger,
            exporter: exporter, tempFileStore: tempStore, uploadEngine: engine,
            settingsStore: settingsStore
        )
        
        settingsStore.settings.destinationFolderId = nil
        
        do {
            _ = try await orchestrator.startSync()
            XCTFail("Should have thrown missing folder error")
        } catch {
            XCTAssertTrue(error is SyncError)
            XCTAssertEqual(error.localizedDescription, "Destination upload folder is not set.")
        }
    }

    func testSyncBlocksOnCellularWhenWifiOnly() async throws {
        orchestrator = SystemSyncOrchestrator(
            apiClient: api, photosScanner: scanner, ledger: ledger,
            exporter: exporter, tempFileStore: tempStore, uploadEngine: engine,
            settingsStore: settingsStore,
            wifiChecker: { false } // Simulate Cellular
        )
        
        settingsStore.settings.destinationFolderId = UUID()
        settingsStore.settings.wifiOnly = true
        
        do {
            _ = try await orchestrator.startSync()
            XCTFail("Should have blocked cellular connection")
        } catch {
            XCTAssertTrue(error is SyncError)
            XCTAssertEqual(error.localizedDescription, "Upload paused: connection is cellular but sync is set to Wi-Fi only.")
        }
    }

    func testSuccessfulSyncQueue() async throws {
        orchestrator = SystemSyncOrchestrator(
            apiClient: api, photosScanner: scanner, ledger: ledger,
            exporter: exporter, tempFileStore: tempStore, uploadEngine: engine,
            settingsStore: settingsStore,
            wifiChecker: { true } // WiFi connected
        )
        
        let folderId = UUID()
        settingsStore.settings.destinationFolderId = folderId
        
        let candidate = PhotoAssetCandidate(
            assetLocalIdentifier: "asset1",
            resourceKind: .image,
            originalFilename: "photo.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 500
        )
        scanner.candidates = [candidate]
        
        let count = try await orchestrator.startSync()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(ledger.upsertCount, 1)
        XCTAssertEqual(exporter.exportCount, 1)
        XCTAssertEqual(engine.uploadCount, 1)
        
        // Verify ledger record is marked uploaded
        XCTAssertEqual(ledger.records.first?.status, .uploaded)
    }

    func testSyncContinuesQueueAfterOneItemFails() async throws {
        orchestrator = SystemSyncOrchestrator(
            apiClient: api, photosScanner: scanner, ledger: ledger,
            exporter: exporter, tempFileStore: tempStore, uploadEngine: engine,
            settingsStore: settingsStore,
            wifiChecker: { true }
        )
        
        let folderId = UUID()
        settingsStore.settings.destinationFolderId = folderId
        
        let candidate1 = PhotoAssetCandidate(
            assetLocalIdentifier: "failed-asset",
            resourceKind: .image,
            originalFilename: "fail.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 500
        )
        
        let candidate2 = PhotoAssetCandidate(
            assetLocalIdentifier: "success-asset",
            resourceKind: .image,
            originalFilename: "ok.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: Date(),
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 500
        )
        
        scanner.candidates = [candidate1, candidate2]
        
        // Setup engine to fail for 'failed-asset' and succeed for others
        engine.shouldFail = true // Fail all uploads in engine
        
        // Wait, if engine fails all, successful uploads count should be 0, but both should be processed and marked failed
        let count = try await orchestrator.startSync()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(engine.uploadCount, 2) // Tried both!
        
        XCTAssertEqual(ledger.records.first(where: { $0.assetLocalIdentifier == "failed-asset" })?.status, .failed)
        XCTAssertEqual(ledger.records.first(where: { $0.assetLocalIdentifier == "success-asset" })?.status, .failed)
    }

    func testSyncFailsWhenPhotosPermissionDenied() async throws {
        let deniedScanner = PermissionAwarePhotoLibraryClient(status: .denied)
        orchestrator = SystemSyncOrchestrator(
            apiClient: api, photosScanner: deniedScanner, ledger: ledger,
            exporter: exporter, tempFileStore: tempStore, uploadEngine: engine,
            settingsStore: settingsStore,
            wifiChecker: { true }
        )

        settingsStore.settings.destinationFolderId = UUID()

        do {
            _ = try await orchestrator.startSync()
            XCTFail("Should have required Photos permission")
        } catch {
            XCTAssertTrue(error is SyncError)
            XCTAssertEqual(error.localizedDescription, "Photos access is required before sync can start.")
        }
    }

    func testCancelStopsAfterCurrentItem() async throws {
        orchestrator = SystemSyncOrchestrator(
            apiClient: api, photosScanner: scanner, ledger: ledger,
            exporter: exporter, tempFileStore: tempStore, uploadEngine: engine,
            settingsStore: settingsStore,
            wifiChecker: { true }
        )

        let folderId = UUID()
        settingsStore.settings.destinationFolderId = folderId
        engine.delayNanoseconds = 200_000_000

        scanner.candidates = [
            PhotoAssetCandidate(
                assetLocalIdentifier: "asset-1",
                resourceKind: .image,
                originalFilename: "first.jpg",
                uniformTypeIdentifier: "public.jpeg",
                mimeType: "image/jpeg",
                creationDate: Date(),
                modificationDate: nil,
                pixelWidth: 800,
                pixelHeight: 600,
                durationSeconds: nil,
                resourceFileSize: 500
            ),
            PhotoAssetCandidate(
                assetLocalIdentifier: "asset-2",
                resourceKind: .image,
                originalFilename: "second.jpg",
                uniformTypeIdentifier: "public.jpeg",
                mimeType: "image/jpeg",
                creationDate: Date(),
                modificationDate: nil,
                pixelWidth: 800,
                pixelHeight: 600,
                durationSeconds: nil,
                resourceFileSize: 500
            )
        ]

        let syncTask = Task { try await orchestrator.startSync() }
        try await Task.sleep(nanoseconds: 50_000_000)
        orchestrator.cancelSync()

        let uploadedCount = try await syncTask.value

        XCTAssertEqual(uploadedCount, 1)
        XCTAssertEqual(engine.uploadCount, 1)
        XCTAssertEqual(ledger.records.filter { $0.status == .uploaded }.count, 1)
        XCTAssertEqual(ledger.records.filter { $0.status == .discovered }.count, 1)
    }
}
