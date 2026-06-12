import Foundation

struct LedgerFactory {
    static func createOrRecoverLedger(dbURL: URL, isCorrupted: inout Bool) -> UploadLedger {
        do {
            return try SQLiteUploadLedger(dbURL: dbURL)
        } catch {
            isCorrupted = true
            let fm = FileManager.default
            let timestamp = Int(Date().timeIntervalSince1970)
            let corruptURL = dbURL.deletingLastPathComponent()
                .appendingPathComponent("UploadLedger.corrupt.\(timestamp).sqlite")
            try? fm.moveItem(at: dbURL, to: corruptURL)
            
            // Fallback to recreating database, or in-memory if disk creation fails
            do {
                return try SQLiteUploadLedger(dbURL: dbURL)
            } catch {
                do {
                    return try SQLiteUploadLedger(dbURL: URL(fileURLWithPath: ":memory:"))
                } catch {
                    return InMemoryUploadLedger()
                }
            }
        }
    }
}

final class ReconciliationService {
    private let apiClient: NexusRelayAPI
    private let photosScanner: PhotoLibraryClient
    private let ledger: UploadLedger

    init(apiClient: NexusRelayAPI, photosScanner: PhotoLibraryClient, ledger: UploadLedger) {
        self.apiClient = apiClient
        self.photosScanner = photosScanner
        self.ledger = ledger
    }

    func reconcile(folderId: UUID) async throws {
        // 1. Fetch backend file names
        var allRemoteFileNames = Set<String>()
        var cursor: String? = nil
        var hasMore = true
        
        while hasMore {
            let content = try await apiClient.listFolderMedia(folderId: folderId, pageSize: 60, cursor: cursor)
            
            // Decodes mediaItems first, fallback to media.items
            let items = content.mediaItems ?? content.media?.items ?? []
            
            for item in items {
                allRemoteFileNames.insert(item.fileName)
            }
            
            cursor = content.media?.nextCursor
            hasMore = (content.media?.hasMore ?? false) && cursor != nil && !(cursor?.isEmpty ?? true)
        }
        
        // 2. Scan local Photos candidates
        let candidates = try await photosScanner.fetchCandidates(includeVideos: true, includeLivePhotoVideo: false)
        
        // 3. Register discovered candidates in local database
        try await ledger.upsertDiscovered(candidates, folderId: folderId)
        
        // 4. Mark matches as synced
        try await ledger.markSyncedByUploadedFileNames(allRemoteFileNames, folderId: folderId)
    }
}
