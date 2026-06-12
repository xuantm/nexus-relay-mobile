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
}

