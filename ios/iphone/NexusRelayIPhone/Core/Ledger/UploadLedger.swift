import Foundation

struct LedgerCounts: Equatable {
    let queued: Int
    let uploaded: Int
    let failed: Int
    let exporting: Int
    let uploading: Int
}

struct LedgerNextBatchSummary: Equatable {
    let photoCount: Int
    let videoCount: Int
    let totalBytes: Int64
}

struct LedgerDashboardSummary: Equatable {
    let counts: LedgerCounts
    let remainingBytes: Int64
    let nextBatch: LedgerNextBatchSummary
}

enum UploadQueueFilter: Equatable {
    case all
    case active
    case failed
}

protocol UploadLedger: AnyObject {
    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws
    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord]
    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord]
    func retryFailed(ids: [String]) async throws
    func markExporting(id: String) async throws
    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws
    func markUploading(id: String) async throws
    func markUploaded(id: String, backendUploadId: UUID) async throws
    func markSyncedByUploadedFileNames(_ fileNames: Set<String>, folderId: UUID) async throws
    func markFailed(id: String, error: String, retryable: Bool) async throws
    func getLedgerCounts() async throws -> LedgerCounts
    func getDashboardSummary(nextBatchLimit: Int) async throws -> LedgerDashboardSummary
    func clearAllRecords() async throws
}

final class InMemoryUploadLedger: UploadLedger {
    private var records: [String: UploadLedgerRecord] = [:]
    private let lock = NSLock()

    init() {}

    func clearAllRecords() async throws {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll()
    }

    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }
        for candidate in candidates {
            let fingerprint = AssetFingerprinter.generateFingerprint(candidate: candidate)
            let suffix = AssetFingerprinter.getFingerprintSuffix(fingerprint: fingerprint)
            let uploadedName = AssetFingerprinter.generateUploadedFilename(candidate: candidate, suffix: suffix)
            let recordId = "\(candidate.assetLocalIdentifier):\(candidate.resourceKind.rawValue):\(suffix):\(folderId.uuidString.lowercased())"
            
            if let existing = records[recordId] {
                records[recordId] = UploadLedgerRecord(
                    id: recordId,
                    assetLocalIdentifier: candidate.assetLocalIdentifier,
                    resourceKind: candidate.resourceKind,
                    fingerprintSuffix: suffix,
                    originalFilename: candidate.originalFilename,
                    uploadedFileName: uploadedName,
                    mimeType: candidate.mimeType,
                    sizeBytes: candidate.resourceFileSize ?? existing.sizeBytes,
                    status: existing.status,
                    backendFolderId: folderId,
                    backendUploadId: existing.backendUploadId,
                    localStagedFileURL: existing.localStagedFileURL,
                    attemptCount: existing.attemptCount,
                    lastAttemptAt: existing.lastAttemptAt,
                    lastError: existing.lastError
                )
            } else {
                records[recordId] = UploadLedgerRecord(
                    id: recordId,
                    assetLocalIdentifier: candidate.assetLocalIdentifier,
                    resourceKind: candidate.resourceKind,
                    fingerprintSuffix: suffix,
                    originalFilename: candidate.originalFilename,
                    uploadedFileName: uploadedName,
                    mimeType: candidate.mimeType,
                    sizeBytes: candidate.resourceFileSize,
                    status: .discovered,
                    backendFolderId: folderId,
                    backendUploadId: nil,
                    localStagedFileURL: nil,
                    attemptCount: 0,
                    lastAttemptAt: nil,
                    lastError: nil
                )
            }
        }
    }

    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord] {
        lock.lock()
        defer { lock.unlock() }
        let eligible = records.values.filter { record in
            let status = record.status
            let eligibleStatus = (status == .discovered || status == .exporting || status == .readyToUpload || status == .uploading || status == .failed)
            return eligibleStatus && record.attemptCount < 3
        }
        
        let sorted = eligible.sorted { a, b in
            if let aTime = a.lastAttemptAt?.timeIntervalSince1970, let bTime = b.lastAttemptAt?.timeIntervalSince1970 {
                if aTime == bTime {
                    return a.id < b.id
                }
                return aTime < bTime
            } else if a.lastAttemptAt != nil {
                return false
            } else if b.lastAttemptAt != nil {
                return true
            } else {
                return a.id < b.id
            }
        }
        return Array(sorted.prefix(limit))
    }

    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] {
        lock.lock()
        defer { lock.unlock() }
        let filtered: [UploadLedgerRecord]
        switch filter {
        case .all:
            filtered = records.values.filter { record in
                let status = record.status
                return status == .discovered || status == .exporting || status == .readyToUpload || status == .uploading || status == .failed
            }
        case .active:
            filtered = records.values.filter { record in
                let status = record.status
                return status == .exporting || status == .uploading
            }
        case .failed:
            filtered = records.values.filter { $0.status == .failed }
        }
        
        func statusPriority(_ status: UploadLedgerStatus) -> Int {
            switch status {
            case .failed: return 0
            case .uploading: return 1
            case .exporting: return 2
            case .readyToUpload: return 3
            default: return 4
            }
        }
        
        let sorted = filtered.sorted { a, b in
            let aPri = statusPriority(a.status)
            let bPri = statusPriority(b.status)
            if aPri != bPri {
                return aPri < bPri
            }
            if let aTime = a.lastAttemptAt?.timeIntervalSince1970, let bTime = b.lastAttemptAt?.timeIntervalSince1970 {
                if aTime == bTime {
                    return a.id < b.id
                }
                return aTime > bTime
            } else if a.lastAttemptAt != nil {
                return true
            } else if b.lastAttemptAt != nil {
                return false
            } else {
                return a.id < b.id
            }
        }
        return Array(sorted.prefix(limit))
    }

    func retryFailed(ids: [String]) async throws {
        lock.lock()
        defer { lock.unlock() }
        for id in ids {
            if let existing = records[id], existing.status == .failed {
                records[id] = UploadLedgerRecord(
                    id: existing.id,
                    assetLocalIdentifier: existing.assetLocalIdentifier,
                    resourceKind: existing.resourceKind,
                    fingerprintSuffix: existing.fingerprintSuffix,
                    originalFilename: existing.originalFilename,
                    uploadedFileName: existing.uploadedFileName,
                    mimeType: existing.mimeType,
                    sizeBytes: existing.sizeBytes,
                    status: .discovered,
                    backendFolderId: existing.backendFolderId,
                    backendUploadId: existing.backendUploadId,
                    localStagedFileURL: existing.localStagedFileURL,
                    attemptCount: 0,
                    lastAttemptAt: nil,
                    lastError: nil
                )
            }
        }
    }

    func markExporting(id: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        if let existing = records[id] {
            records[id] = updateStatus(record: existing, status: .exporting)
        }
    }

    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws {
        lock.lock()
        defer { lock.unlock() }
        if let existing = records[id] {
            records[id] = UploadLedgerRecord(
                id: existing.id,
                assetLocalIdentifier: existing.assetLocalIdentifier,
                resourceKind: existing.resourceKind,
                fingerprintSuffix: existing.fingerprintSuffix,
                originalFilename: existing.originalFilename,
                uploadedFileName: existing.uploadedFileName,
                mimeType: existing.mimeType,
                sizeBytes: sizeBytes,
                status: .readyToUpload,
                backendFolderId: existing.backendFolderId,
                backendUploadId: existing.backendUploadId,
                localStagedFileURL: stagedFileURL,
                attemptCount: existing.attemptCount,
                lastAttemptAt: existing.lastAttemptAt,
                lastError: existing.lastError
            )
        }
    }

    func markUploading(id: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        if let existing = records[id] {
            records[id] = updateStatus(record: existing, status: .uploading)
        }
    }

    func markUploaded(id: String, backendUploadId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }
        if let existing = records[id] {
            records[id] = UploadLedgerRecord(
                id: existing.id,
                assetLocalIdentifier: existing.assetLocalIdentifier,
                resourceKind: existing.resourceKind,
                fingerprintSuffix: existing.fingerprintSuffix,
                originalFilename: existing.originalFilename,
                uploadedFileName: existing.uploadedFileName,
                mimeType: existing.mimeType,
                sizeBytes: existing.sizeBytes,
                status: .uploaded,
                backendFolderId: existing.backendFolderId,
                backendUploadId: backendUploadId,
                localStagedFileURL: existing.localStagedFileURL,
                attemptCount: existing.attemptCount,
                lastAttemptAt: existing.lastAttemptAt,
                lastError: existing.lastError
            )
        }
    }

    func markSyncedByUploadedFileNames(_ fileNames: Set<String>, folderId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }
        for (id, record) in records {
            if fileNames.contains(record.uploadedFileName) && record.backendFolderId == folderId {
                records[id] = updateStatus(record: record, status: .synced)
            }
        }
    }

    func markFailed(id: String, error: String, retryable: Bool) async throws {
        lock.lock()
        defer { lock.unlock() }
        if let existing = records[id] {
            let nextAttempts = retryable ? existing.attemptCount + 1 : 99
            records[id] = UploadLedgerRecord(
                id: existing.id,
                assetLocalIdentifier: existing.assetLocalIdentifier,
                resourceKind: existing.resourceKind,
                fingerprintSuffix: existing.fingerprintSuffix,
                originalFilename: existing.originalFilename,
                uploadedFileName: existing.uploadedFileName,
                mimeType: existing.mimeType,
                sizeBytes: existing.sizeBytes,
                status: .failed,
                backendFolderId: existing.backendFolderId,
                backendUploadId: existing.backendUploadId,
                localStagedFileURL: existing.localStagedFileURL,
                attemptCount: nextAttempts,
                lastAttemptAt: Date(),
                lastError: error
            )
        }
    }

    func getLedgerCounts() async throws -> LedgerCounts {
        lock.lock()
        defer { lock.unlock() }
        var queued = 0
        var uploaded = 0
        var failed = 0
        var exporting = 0
        var uploading = 0

        for record in records.values {
            switch record.status {
            case .discovered, .readyToUpload:
                queued += 1
            case .uploaded, .synced:
                uploaded += 1
            case .failed:
                failed += 1
            case .exporting:
                exporting += 1
            case .uploading:
                uploading += 1
            default:
                break
            }
        }

        return LedgerCounts(queued: queued, uploaded: uploaded, failed: failed, exporting: exporting, uploading: uploading)
    }

    func getDashboardSummary(nextBatchLimit: Int) async throws -> LedgerDashboardSummary {
        let counts = try await getLedgerCounts()
        
        lock.lock()
        let eligibleForRemaining = records.values.filter { record in
            let status = record.status
            return status == .discovered || status == .exporting || status == .readyToUpload || status == .uploading || status == .failed
        }
        let remainingBytes = eligibleForRemaining.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        lock.unlock()

        let batchRecords = try await nextUploadBatch(limit: nextBatchLimit)
        let photoCount = batchRecords.filter { $0.resourceKind == .image }.count
        let videoCount = batchRecords.filter { $0.resourceKind == .video || $0.resourceKind == .livePhotoVideo }.count
        let totalBytes = batchRecords.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }

        return LedgerDashboardSummary(
            counts: counts,
            remainingBytes: remainingBytes,
            nextBatch: LedgerNextBatchSummary(photoCount: photoCount, videoCount: videoCount, totalBytes: totalBytes)
        )
    }

    private func updateStatus(record: UploadLedgerRecord, status: UploadLedgerStatus) -> UploadLedgerRecord {
        return UploadLedgerRecord(
            id: record.id,
            assetLocalIdentifier: record.assetLocalIdentifier,
            resourceKind: record.resourceKind,
            fingerprintSuffix: record.fingerprintSuffix,
            originalFilename: record.originalFilename,
            uploadedFileName: record.uploadedFileName,
            mimeType: record.mimeType,
            sizeBytes: record.sizeBytes,
            status: status,
            backendFolderId: record.backendFolderId,
            backendUploadId: record.backendUploadId,
            localStagedFileURL: record.localStagedFileURL,
            attemptCount: record.attemptCount,
            lastAttemptAt: record.lastAttemptAt,
            lastError: record.lastError
        )
    }
}

