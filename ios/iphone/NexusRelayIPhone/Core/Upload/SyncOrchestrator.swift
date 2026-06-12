import Foundation
import Network
import OSLog

private let syncLogger = Logger(subsystem: "com.nexusrelay.iphone", category: "sync")


protocol SyncOrchestrator: AnyObject {
    var isSyncing: Bool { get }
    func startSync() async throws -> Int // Returns number of successfully uploaded assets
    func cancelSync()
}

final class SystemSyncOrchestrator: SyncOrchestrator {
    private let apiClient: NexusRelayAPI
    private let photosScanner: PhotoLibraryClient
    private let ledger: UploadLedger
    private let exporter: AssetExporter
    private let tempFileStore: TemporaryFileStore
    private let uploadEngine: UploadEngine
    private let settingsStore: SettingsStore
    private let policy: UploadPolicy
    private let onScanCompleted: (@Sendable (Int) async -> Void)?

    private let wifiChecker: () -> Bool
    private let lock = NSLock()
    private var _isSyncing = false
    private var _cancelRequested = false

    var isSyncing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSyncing
    }

    func cancelSync() {
        lock.lock()
        _cancelRequested = true
        lock.unlock()
    }

    init(
        apiClient: NexusRelayAPI,
        photosScanner: PhotoLibraryClient,
        ledger: UploadLedger,
        exporter: AssetExporter,
        tempFileStore: TemporaryFileStore,
        uploadEngine: UploadEngine,
        settingsStore: SettingsStore,
        policy: UploadPolicy = .nexusRelayDefault,
        onScanCompleted: (@Sendable (Int) async -> Void)? = nil,
        wifiChecker: @escaping () -> Bool = {
            let monitor = NWPathMonitor()
            let semaphore = DispatchSemaphore(value: 0)
            var isWifi = false
            monitor.pathUpdateHandler = { path in
                isWifi = path.usesInterfaceType(.wifi)
                semaphore.signal()
            }
            let queue = DispatchQueue(label: "reachability")
            monitor.start(queue: queue)
            _ = semaphore.wait(timeout: .now() + 2.0)
            monitor.cancel()
            return isWifi
        }
    ) {
        self.apiClient = apiClient
        self.photosScanner = photosScanner
        self.ledger = ledger
        self.exporter = exporter
        self.tempFileStore = tempFileStore
        self.uploadEngine = uploadEngine
        self.settingsStore = settingsStore
        self.policy = policy
        self.wifiChecker = wifiChecker
        self.onScanCompleted = onScanCompleted
    }

    func startSync() async throws -> Int {
        lock.lock()
        guard !_isSyncing else {
            lock.unlock()
            return 0
        }
        _isSyncing = true
        _cancelRequested = false
        lock.unlock()
        
        defer {
            lock.lock()
            _isSyncing = false
            lock.unlock()
        }

        let settings = settingsStore.settings
        guard let folderId = settings.destinationFolderId else {
            throw SyncError.missingFolder
        }

        let photosAuthorization = await ensurePhotosAuthorization()
        guard photosAuthorization == .authorized || photosAuthorization == .limited else {
            throw SyncError.photosPermissionRequired
        }

        // 1. Check network constraints
        if settings.wifiOnly && !isWifiConnected() {
            throw SyncError.cellularConnectionBlocked
        }

        var uploadedCount = 0

        // 2. Scan and register new files
        let scanStart = Date()
        let candidates = try await photosScanner.fetchCandidates(
            includeVideos: settings.includeVideos,
            includeLivePhotoVideo: settings.includeLivePhotoVideo
        )
        syncLogger.info(
            "sync.scan.completed count=\(candidates.count) elapsedMs=\(self.loggingMilliseconds(since: scanStart)) itemsPerSec=\(self.loggingItemsPerSecond(count: candidates.count, since: scanStart))"
        )
        try await ledger.upsertDiscovered(candidates, folderId: folderId)
        await onScanCompleted?(candidates.count)
        if isCancellationRequested() {
            try? tempFileStore.cleanStaleFiles()
            return uploadedCount
        }

        // 3. Process batches
        var hasMore = true
        let batchLimit = 50
        var processedRecordIds = Set<String>()

        while hasMore {
            if isCancellationRequested() {
                break
            }

            // Respect low power mode during queue execution
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                break
            }

            let batch = try await ledger.nextUploadBatch(limit: batchLimit)
            let pendingBatch = batch.filter { !processedRecordIds.contains($0.id) }
            if pendingBatch.isEmpty {
                hasMore = false
                break
            }

            syncLogger.info("sync.batch.started count=\(pendingBatch.count) concurrency=\(max(self.policy.recordUploadConcurrency, 1))")
            let batchStart = Date()
            processedRecordIds.formUnion(pendingBatch.map(\.id))
            let batchUploadedCount = try await processBatchConcurrently(
                pendingBatch,
                folderId: folderId,
                settings: settings
            )
            uploadedCount += batchUploadedCount
            syncLogger.info(
                "sync.batch.completed count=\(pendingBatch.count) uploaded=\(batchUploadedCount) elapsedMs=\(self.loggingMilliseconds(since: batchStart)) recordsPerSec=\(self.loggingItemsPerSecond(count: pendingBatch.count, since: batchStart))"
            )

            if isCancellationRequested() {
                break
            }
        }

        // Clean any leftover stale files
        try? tempFileStore.cleanStaleFiles()
        
        return uploadedCount
    }

    private func processBatchConcurrently(
        _ records: [UploadLedgerRecord],
        folderId: UUID,
        settings: AppSettings
    ) async throws -> Int {
        let concurrency = max(policy.recordUploadConcurrency, 1)
        var iterator = records.makeIterator()
        var uploadedCount = 0

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<concurrency {
                guard !isCancellationRequested(), let record = iterator.next() else { break }
                group.addTask { [self] in
                    try await processRecord(record, folderId: folderId, settings: settings)
                }
            }

            while let didUpload = try await group.next() {
                if didUpload {
                    uploadedCount += 1
                }

                guard !isCancellationRequested(), let next = iterator.next() else {
                    continue
                }

                group.addTask { [self] in
                    try await processRecord(next, folderId: folderId, settings: settings)
                }
            }
        }

        return uploadedCount
    }

    private func processRecord(
        _ record: UploadLedgerRecord,
        folderId: UUID,
        settings: AppSettings
    ) async throws -> Bool {
        let recordStart = Date()
        do {
            try await ledger.markExporting(id: record.id)

            let candidate = PhotoAssetCandidate(
                assetLocalIdentifier: record.assetLocalIdentifier,
                resourceKind: record.resourceKind,
                originalFilename: record.originalFilename,
                uniformTypeIdentifier: record.mimeType,
                mimeType: record.mimeType,
                creationDate: record.lastAttemptAt,
                modificationDate: nil,
                pixelWidth: 0,
                pixelHeight: 0,
                durationSeconds: nil,
                resourceFileSize: record.sizeBytes
            )

            let stagedURL = try tempFileStore.getStagedFileURL(
                recordId: record.id,
                fileName: record.uploadedFileName
            )

            try await exporter.exportOriginalResource(
                candidate: candidate,
                outputURL: stagedURL,
                allowNetworkAccess: !settings.wifiOnly
            )

            let actualSize = try getFileSize(at: stagedURL)
            try await ledger.markReady(id: record.id, stagedFileURL: stagedURL, sizeBytes: actualSize)
            try await ledger.markUploading(id: record.id)

            let updatedRecord = UploadLedgerRecord(
                id: record.id,
                assetLocalIdentifier: record.assetLocalIdentifier,
                resourceKind: record.resourceKind,
                fingerprintSuffix: record.fingerprintSuffix,
                originalFilename: record.originalFilename,
                uploadedFileName: record.uploadedFileName,
                mimeType: record.mimeType,
                sizeBytes: actualSize,
                status: .readyToUpload,
                backendFolderId: folderId,
                backendUploadId: nil,
                localStagedFileURL: stagedURL,
                attemptCount: record.attemptCount,
                lastAttemptAt: Date(),
                lastError: nil
            )

            let uploadId = try await uploadEngine.upload(record: updatedRecord, folderId: folderId)

            try await ledger.markUploaded(id: record.id, backendUploadId: uploadId)
            try? tempFileStore.deleteStagedFile(recordId: record.id)
            syncLogger.info(
                "sync.record.completed id=\(record.id, privacy: .public) bytes=\(actualSize) elapsedMs=\(self.loggingMilliseconds(since: recordStart)) bytesPerSec=\(self.loggingBytesPerSecond(bytes: actualSize, since: recordStart))"
            )
            return true
        } catch {
            let retryable = isRetryableError(error)
            let userFacingMessage = UserFacingSyncIssue.from(error: error).message
            try await ledger.markFailed(id: record.id, error: userFacingMessage, retryable: retryable)
            try? tempFileStore.deleteStagedFile(recordId: record.id)
            syncLogger.error(
                "sync.record.failed id=\(record.id, privacy: .public) elapsedMs=\(self.loggingMilliseconds(since: recordStart)) error=\(userFacingMessage, privacy: .private)"
            )
            return false
        }
    }

    private func isCancellationRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelRequested
    }

    private func isWifiConnected() -> Bool {
        return wifiChecker()
    }

    private func ensurePhotosAuthorization() async -> PhotoLibraryAuthorizationStatus {
        let currentStatus = photosScanner.authorizationStatus()
        if currentStatus == .notDetermined {
            return await photosScanner.requestAuthorization()
        }

        return currentStatus
    }

    private func getFileSize(at url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return attrs[.size] as? Int64 ?? 0
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if let exportError = error as? ExportError {
            switch exportError {
            case .networkAccessRequired:
                return true // Can retry when on Wi-Fi
            default:
                return false
            }
        }
        
        // Network timeout/offline is retryable
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorTimedOut ||
                   nsError.code == NSURLErrorCannotFindHost ||
                   nsError.code == NSURLErrorCannotConnectToHost ||
                   nsError.code == NSURLErrorNetworkConnectionLost ||
                   nsError.code == NSURLErrorCannotParseResponse ||
                   nsError.code == NSURLErrorNotConnectedToInternet
        }
        
        return true
    }

    private func loggingMilliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private func loggingItemsPerSecond(count: Int, since start: Date) -> Int {
        let elapsed = max(Date().timeIntervalSince(start), 0.001)
        return Int((Double(count) / elapsed).rounded())
    }

    private func loggingBytesPerSecond(bytes: Int64, since start: Date) -> Int64 {
        let elapsed = max(Date().timeIntervalSince(start), 0.001)
        return Int64((Double(bytes) / elapsed).rounded())
    }
}

enum SyncError: Error, LocalizedError {
    case missingFolder
    case cellularConnectionBlocked
    case photosPermissionRequired

    var errorDescription: String? {
        switch self {
        case .missingFolder: return "Destination upload folder is not set."
        case .cellularConnectionBlocked: return "Upload paused: connection is cellular but sync is set to Wi-Fi only."
        case .photosPermissionRequired: return "Photos access is required before sync can start."
        }
    }
}
