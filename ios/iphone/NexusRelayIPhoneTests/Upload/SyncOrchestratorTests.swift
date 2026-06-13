import XCTest
@testable import NexusRelayIPhone

// MARK: - Mocks for Testing
final class MockSettingsStore: SettingsStore {
    var settings: AppSettings = .defaults
}

final class MockAssetExporter: AssetExporter {
    private let lock = NSLock()
    private var _exportCount = 0
    var exportCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _exportCount
    }
    var shouldFail = false

    func exportOriginalResource(candidate: PhotoAssetCandidate, outputURL: URL, allowNetworkAccess: Bool) async throws {
        lock.lock()
        _exportCount += 1
        lock.unlock()

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
    private let lock = NSLock()
    private var _getStagedURLCount = 0
    private var _deleteCount = 0
    private var _cleanCount = 0
    var getStagedURLCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _getStagedURLCount
    }
    var deleteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _deleteCount
    }
    var cleanCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _cleanCount
    }
    
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    
    init() {
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    
    func getStagedFileURL(recordId: String, fileName: String) throws -> URL {
        lock.lock()
        _getStagedURLCount += 1
        lock.unlock()

        let dir = root.appendingPathComponent(recordId.replacingOccurrences(of: ":", with: "_"))
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
    
    func deleteStagedFile(recordId: String) throws {
        lock.lock()
        _deleteCount += 1
        lock.unlock()

        let dir = root.appendingPathComponent(recordId.replacingOccurrences(of: ":", with: "_"))
        try? FileManager.default.removeItem(at: dir)
    }
    
    func cleanStaleFiles() throws {
        lock.lock()
        _cleanCount += 1
        lock.unlock()
    }
    
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

final class MockUploadEngine: UploadEngine {
    private struct UploadWaiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var _uploadCount = 0
    private var activeUploads = 0
    private var _maxConcurrentUploads = 0
    private var uploadWaiters: [UploadWaiter] = []

    var uploadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _uploadCount
    }
    var maxConcurrentUploads: Int {
        lock.lock()
        defer { lock.unlock() }
        return _maxConcurrentUploads
    }
    var shouldFail = false
    var delayNanoseconds: UInt64 = 0

    func upload(record: UploadLedgerRecord, folderId: UUID) async throws -> UUID {
        let continuations = recordUploadStarted()
        continuations.forEach { $0.resume() }

        defer {
            lock.lock()
            activeUploads -= 1
            lock.unlock()
        }

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if shouldFail {
            throw APIError.requestFailed(statusCode: 500, message: "mock-server-failure")
        }
        return UUID()
    }

    func waitForUploadCount(_ target: Int) async {
        lock.lock()
        let isAlreadyReached = _uploadCount >= target
        lock.unlock()
        if isAlreadyReached { return }

        await withCheckedContinuation { continuation in
            var shouldResume = false

            lock.lock()
            if _uploadCount >= target {
                shouldResume = true
            } else {
                uploadWaiters.append(UploadWaiter(target: target, continuation: continuation))
            }
            lock.unlock()

            if shouldResume {
                continuation.resume()
            }
        }
    }

    private func recordUploadStarted() -> [CheckedContinuation<Void, Never>] {
        lock.lock()
        defer { lock.unlock() }

        _uploadCount += 1
        activeUploads += 1
        _maxConcurrentUploads = max(_maxConcurrentUploads, activeUploads)

        var readyContinuations: [CheckedContinuation<Void, Never>] = []
        var pendingWaiters: [UploadWaiter] = []
        for waiter in uploadWaiters {
            if _uploadCount >= waiter.target {
                readyContinuations.append(waiter.continuation)
            } else {
                pendingWaiters.append(waiter)
            }
        }
        uploadWaiters = pendingWaiters
        return readyContinuations
    }
}

final class MockUploadLedger: UploadLedger {
    private let lock = NSLock()
    private var _records: [UploadLedgerRecord] = []
    var records: [UploadLedgerRecord] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _records
        }
        set {
            lock.lock()
            _records = newValue
            lock.unlock()
        }
    }
    var upsertCount = 0
    var nextBatchCount = 0
    
    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }

        upsertCount += 1
        for candidate in candidates {
            if !_records.contains(where: { $0.assetLocalIdentifier == candidate.assetLocalIdentifier }) {
                _records.append(UploadLedgerRecord(
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
                    lastError: nil,
                    clientSyncId: UUID()
                ))
            }
        }
    }

    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord] {
        lock.lock()
        defer { lock.unlock() }

        nextBatchCount += 1
        let uploadableStatuses: [UploadLedgerStatus] = [.discovered, .exporting, .readyToUpload, .uploading, .failed]
        let batch = _records.filter { uploadableStatuses.contains($0.status) && $0.attemptCount < 3 }
            .prefix(limit)
        return Array(batch)
    }

    func markExporting(id: String) async throws {
        lock.lock()
        defer { lock.unlock() }

        if let idx = _records.firstIndex(where: { $0.id == id }) {
            let r = _records[idx]
            _records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                status: .exporting, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                localStagedFileURL: r.localStagedFileURL, attemptCount: r.attemptCount,
                lastAttemptAt: r.lastAttemptAt, lastError: r.lastError, clientSyncId: r.clientSyncId
            )
        }
    }

    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws {
        lock.lock()
        defer { lock.unlock() }

        if let idx = _records.firstIndex(where: { $0.id == id }) {
            let r = _records[idx]
            _records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: sizeBytes,
                status: .readyToUpload, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                localStagedFileURL: stagedFileURL, attemptCount: r.attemptCount,
                lastAttemptAt: r.lastAttemptAt, lastError: r.lastError, clientSyncId: r.clientSyncId
            )
        }
    }

    func markUploading(id: String) async throws {
        lock.lock()
        defer { lock.unlock() }

         if let idx = _records.firstIndex(where: { $0.id == id }) {
             let r = _records[idx]
             _records[idx] = UploadLedgerRecord(
                 id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                 fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                 uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                 status: .uploading, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                 localStagedFileURL: r.localStagedFileURL, attemptCount: r.attemptCount,
                 lastAttemptAt: r.lastAttemptAt, lastError: r.lastError, clientSyncId: r.clientSyncId
             )
         }
    }

    func markUploaded(id: String, backendUploadId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }

        if let idx = _records.firstIndex(where: { $0.id == id }) {
            let r = _records[idx]
            _records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                status: .uploaded, backendFolderId: r.backendFolderId, backendUploadId: backendUploadId,
                localStagedFileURL: r.localStagedFileURL, attemptCount: r.attemptCount,
                lastAttemptAt: r.lastAttemptAt, lastError: r.lastError, clientSyncId: r.clientSyncId
            )
        }
    }

    func markSyncedByUploadedFileNames(_ fileNames: Set<String>, folderId: UUID) async throws {}

    func markFailed(id: String, error: String, retryable: Bool) async throws {
        lock.lock()
        defer { lock.unlock() }

        if let idx = _records.firstIndex(where: { $0.id == id }) {
            let r = _records[idx]
            let nextAttemptCount = retryable ? r.attemptCount + 1 : 99
            _records[idx] = UploadLedgerRecord(
                id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                status: .failed, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                localStagedFileURL: r.localStagedFileURL, attemptCount: nextAttemptCount,
                lastAttemptAt: Date(), lastError: error, clientSyncId: r.clientSyncId
            )
        }
    }

    func getLedgerCounts() async throws -> LedgerCounts {
        lock.lock()
        defer { lock.unlock() }

        let queued = _records.filter { $0.status == .discovered || $0.status == .readyToUpload }.count
        let uploaded = _records.filter { $0.status == .uploaded || $0.status == .synced }.count
        let failed = _records.filter { $0.status == .failed }.count
        let exporting = _records.filter { $0.status == .exporting }.count
        let uploading = _records.filter { $0.status == .uploading }.count
        return LedgerCounts(queued: queued, uploaded: uploaded, failed: failed, exporting: exporting, uploading: uploading)
    }

    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] {
        lock.lock()
        defer { lock.unlock() }

        let filtered: [UploadLedgerRecord]
        switch filter {
        case .all:
            filtered = _records
        case .active:
            filtered = _records.filter { $0.status == .exporting || $0.status == .readyToUpload || $0.status == .uploading }
        case .failed:
            filtered = _records.filter { $0.status == .failed }
        }
        return Array(filtered.prefix(limit))
    }

    func retryFailed(ids: [String]) async throws {
        lock.lock()
        defer { lock.unlock() }

        for id in ids {
            if let idx = _records.firstIndex(where: { $0.id == id }) {
                let r = _records[idx]
                _records[idx] = UploadLedgerRecord(
                    id: r.id, assetLocalIdentifier: r.assetLocalIdentifier, resourceKind: r.resourceKind,
                    fingerprintSuffix: r.fingerprintSuffix, originalFilename: r.originalFilename,
                    uploadedFileName: r.uploadedFileName, mimeType: r.mimeType, sizeBytes: r.sizeBytes,
                    status: .discovered, backendFolderId: r.backendFolderId, backendUploadId: r.backendUploadId,
                    localStagedFileURL: r.localStagedFileURL, attemptCount: 0,
                    lastAttemptAt: r.lastAttemptAt, lastError: r.lastError, clientSyncId: r.clientSyncId
                )
            }
        }
    }

    func getDashboardSummary(nextBatchLimit: Int) async throws -> LedgerDashboardSummary {
        let counts = try await getLedgerCounts()
        return LedgerDashboardSummary(
            counts: counts,
            remainingBytes: 0,
            nextBatch: LedgerNextBatchSummary(photoCount: 0, videoCount: 0, totalBytes: 0)
        )
    }

    func clearAllRecords() async throws {
        lock.lock()
        defer { lock.unlock() }
        _records.removeAll()
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

    func testSyncUsesBoundedUploadConcurrency() async throws {
        func makeOrchestrator(
            recordUploadConcurrency: Int
        ) -> (orchestrator: SystemSyncOrchestrator, engine: MockUploadEngine, tempStore: MockTemporaryFileStore) {
            let localApi = MockNexusRelayAPI()
            let localScanner = MockPhotoLibraryClient()
            let localLedger = MockUploadLedger()
            let localExporter = MockAssetExporter()
            let localTempStore = MockTemporaryFileStore()
            let localEngine = MockUploadEngine()
            let localSettingsStore = MockSettingsStore()
            localSettingsStore.settings.destinationFolderId = UUID()
            localEngine.delayNanoseconds = 200_000_000
            localScanner.candidates = (0..<4).map { index in
                PhotoAssetCandidate(
                    assetLocalIdentifier: "asset-\(index)",
                    resourceKind: .image,
                    originalFilename: "IMG_\(index).HEIC",
                    uniformTypeIdentifier: "public.heic",
                    mimeType: "image/heic",
                    creationDate: Date(),
                    modificationDate: nil,
                    pixelWidth: 100,
                    pixelHeight: 100,
                    durationSeconds: nil,
                    resourceFileSize: 500
                )
            }

            let localOrchestrator = SystemSyncOrchestrator(
                apiClient: localApi,
                photosScanner: localScanner,
                ledger: localLedger,
                exporter: localExporter,
                tempFileStore: localTempStore,
                uploadEngine: localEngine,
                settingsStore: localSettingsStore,
                policy: UploadPolicy(
                    multipartStreamMaxBytes: 50,
                    directStreamMaxBytes: 100,
                    chunkSizeBytes: 50,
                    maxRetries: 1,
                    foregroundChunkConcurrency: 1,
                    backgroundChunkConcurrency: 1,
                    recordUploadConcurrency: recordUploadConcurrency,
                    progressThrottleMilliseconds: 300,
                    chunkCopyBufferSize: 64 * 1024
                ),
                wifiChecker: { true }
            )

            return (localOrchestrator, localEngine, localTempStore)
        }

        let sequential = makeOrchestrator(recordUploadConcurrency: 1)
        defer { sequential.tempStore.cleanup() }
        let sequentialUploaded = try await sequential.orchestrator.startSync()

        let parallel = makeOrchestrator(recordUploadConcurrency: 2)
        defer { parallel.tempStore.cleanup() }
        let parallelUploaded = try await parallel.orchestrator.startSync()

        XCTAssertEqual(sequentialUploaded, 4)
        XCTAssertEqual(parallelUploaded, 4)
        XCTAssertEqual(sequential.engine.uploadCount, 4)
        XCTAssertEqual(parallel.engine.uploadCount, 4)
        XCTAssertEqual(sequential.engine.maxConcurrentUploads, 1)
        XCTAssertEqual(parallel.engine.maxConcurrentUploads, 2)
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
            policy: UploadPolicy(
                multipartStreamMaxBytes: 50,
                directStreamMaxBytes: 100,
                chunkSizeBytes: 50,
                maxRetries: 1,
                foregroundChunkConcurrency: 1,
                backgroundChunkConcurrency: 1,
                recordUploadConcurrency: 1,
                progressThrottleMilliseconds: 300,
                chunkCopyBufferSize: 64 * 1024
            ),
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
        await engine.waitForUploadCount(1)
        orchestrator.cancelSync()

        let uploadedCount = try await syncTask.value

        XCTAssertEqual(uploadedCount, 1)
        XCTAssertEqual(engine.uploadCount, 1)
        XCTAssertEqual(ledger.records.filter { $0.status == .uploaded }.count, 1)
        XCTAssertEqual(ledger.records.filter { $0.status != .uploaded }.count, 1)
    }
}
