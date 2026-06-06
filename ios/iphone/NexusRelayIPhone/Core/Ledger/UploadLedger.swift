import Foundation

struct LedgerCounts: Equatable {
    let queued: Int
    let uploaded: Int
    let failed: Int
    let exporting: Int
    let uploading: Int
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
    func markSyncedByFingerprintSuffixes(_ suffixes: Set<String>, folderId: UUID) async throws
    func markFailed(id: String, error: String, retryable: Bool) async throws
    func getLedgerCounts() async throws -> LedgerCounts
}

