import Foundation
import SQLite3

final class SQLiteUploadLedger: UploadLedger {
    private var db: OpaquePointer?
    private let dbURL: URL
    private let lock = NSLock()

    init(dbURL: URL) throws {
        self.dbURL = dbURL
        do {
            try openDatabase()
            try createTables()
        } catch {
            closeDatabase()
            throw error
        }
    }

    deinit {
        closeDatabase()
    }

    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    private func openDatabase() throws {
        let path = dbURL.path.contains(":memory:") ? ":memory:" : dbURL.path
        
        if path != ":memory:" {
            try? FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let error = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown error"
            throw DatabaseError.openFailed(error)
        }
        
        // Enable WAL mode for safe concurrent reads/writes across connections.
        // Fallback to standard journal mode if WAL fails (e.g. disk I/O error or filesystem limitation).
        do {
            try execute("PRAGMA journal_mode=WAL;")
        } catch {
            try? execute("PRAGMA journal_mode=DELETE;")
        }
        
        // Allow up to 5 seconds wait when another connection holds a write lock
        sqlite3_busy_timeout(db, 5000)
    }

    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS upload_ledger (
            id TEXT PRIMARY KEY,
            asset_local_identifier TEXT NOT NULL,
            resource_kind TEXT NOT NULL,
            fingerprint_suffix TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            uploaded_file_name TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size_bytes INTEGER,
            status TEXT NOT NULL,
            backend_folder_id TEXT,
            backend_upload_id TEXT,
            local_staged_file_url TEXT,
            attempt_count INTEGER DEFAULT 0,
            last_attempt_at INTEGER,
            last_error TEXT
        );
        DROP INDEX IF EXISTS idx_ledger_unique;
        """
        
        try execute(sql)
    }

    private func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<Int8>? = nil
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if result != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            if let errorMsg = errorMsg {
                sqlite3_free(errorMsg)
            }
            throw DatabaseError.executionFailed(error)
        }
    }

    func upsertDiscovered(_ candidates: [PhotoAssetCandidate], folderId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard !candidates.isEmpty else { return }
        
        let sql = """
        INSERT INTO upload_ledger (
            id, asset_local_identifier, resource_kind, fingerprint_suffix,
            original_filename, uploaded_file_name, mime_type, size_bytes,
            status, backend_folder_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'discovered', ?)
        ON CONFLICT(id) DO UPDATE SET
            original_filename = excluded.original_filename,
            uploaded_file_name = excluded.uploaded_file_name,
            mime_type = excluded.mime_type,
            size_bytes = excluded.size_bytes;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        
        defer { sqlite3_finalize(stmt) }

        try execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            for candidate in candidates {
                let fingerprint = AssetFingerprinter.generateFingerprint(candidate: candidate)
                let suffix = AssetFingerprinter.getFingerprintSuffix(fingerprint: fingerprint)
                let uploadedName = AssetFingerprinter.generateUploadedFilename(candidate: candidate, suffix: suffix)
                let recordId = "\(candidate.assetLocalIdentifier):\(candidate.resourceKind.rawValue):\(suffix):\(folderId.uuidString.lowercased())"
                
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                
                sqlite3_bind_text(stmt, 1, recordId, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, candidate.assetLocalIdentifier, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, candidate.resourceKind.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, suffix, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, candidate.originalFilename, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 6, uploadedName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 7, candidate.mimeType, -1, SQLITE_TRANSIENT)
                if let size = candidate.resourceFileSize {
                    sqlite3_bind_int64(stmt, 8, size)
                } else {
                    sqlite3_bind_null(stmt, 8)
                }
                sqlite3_bind_text(stmt, 9, folderId.uuidString.lowercased(), -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DatabaseError.executionFailed(errorMessage())
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func nextUploadBatch(limit: Int) async throws -> [UploadLedgerRecord] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT id, asset_local_identifier, resource_kind, fingerprint_suffix,
               original_filename, uploaded_file_name, mime_type, size_bytes,
               status, backend_folder_id, backend_upload_id, local_staged_file_url,
               attempt_count, last_attempt_at, last_error
        FROM upload_ledger
        WHERE status IN ('discovered', 'exporting', 'readyToUpload', 'uploading', 'failed') AND attempt_count < 3
        ORDER BY last_attempt_at ASC, id ASC
        LIMIT ?;
        """
        
        return try queryRecords(sql: sql, params: [limit])
    }

    func listQueueRecords(filter: UploadQueueFilter, limit: Int) async throws -> [UploadLedgerRecord] {
        lock.lock()
        defer { lock.unlock() }
        let statusClause: String
        switch filter {
        case .all:
            statusClause = "status IN ('discovered', 'exporting', 'readyToUpload', 'uploading', 'failed')"
        case .active:
            statusClause = "status IN ('exporting', 'uploading')"
        case .failed:
            statusClause = "status = 'failed'"
        }

        let sql = """
        SELECT id, asset_local_identifier, resource_kind, fingerprint_suffix,
               original_filename, uploaded_file_name, mime_type, size_bytes,
               status, backend_folder_id, backend_upload_id, local_staged_file_url,
               attempt_count, last_attempt_at, last_error
        FROM upload_ledger
        WHERE \(statusClause)
        ORDER BY
          CASE status
            WHEN 'failed' THEN 0
            WHEN 'uploading' THEN 1
            WHEN 'exporting' THEN 2
            WHEN 'readyToUpload' THEN 3
            ELSE 4
          END,
          last_attempt_at DESC,
          id ASC
        LIMIT ?;
        """

        return try queryRecords(sql: sql, params: [limit])
    }

    func retryFailed(ids: [String]) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.isEmpty else { return }

        let sql = """
        UPDATE upload_ledger
        SET status = 'discovered',
            attempt_count = 0,
            last_error = NULL,
            last_attempt_at = NULL
        WHERE id = ? AND status = 'failed';
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for id in ids {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw DatabaseError.executionFailed(errorMessage())
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func queryRecords(sql: String, params: [Any]) throws -> [UploadLedgerRecord] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        bind(params, to: stmt)

        var records: [UploadLedgerRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            records.append(readRecord(from: stmt))
        }
        return records
    }

    private func bind(_ params: [Any], to stmt: OpaquePointer?) {
        for (index, param) in params.enumerated() {
            let bindIndex = Int32(index + 1)
            if let strVal = param as? String {
                sqlite3_bind_text(stmt, bindIndex, strVal, -1, SQLITE_TRANSIENT)
            } else if let intVal = param as? Int64 {
                sqlite3_bind_int64(stmt, bindIndex, intVal)
            } else if let intVal = param as? Int {
                sqlite3_bind_int64(stmt, bindIndex, Int64(intVal))
            } else {
                sqlite3_bind_null(stmt, bindIndex)
            }
        }
    }

    private func readRecord(from stmt: OpaquePointer?) -> UploadLedgerRecord {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let assetId = String(cString: sqlite3_column_text(stmt, 1))
        let kindRaw = String(cString: sqlite3_column_text(stmt, 2))
        let suffix = String(cString: sqlite3_column_text(stmt, 3))
        let originalFilename = String(cString: sqlite3_column_text(stmt, 4))
        let uploadedFileName = String(cString: sqlite3_column_text(stmt, 5))
        let mimeType = String(cString: sqlite3_column_text(stmt, 6))
        let sizeBytes: Int64? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7)
        let statusRaw = String(cString: sqlite3_column_text(stmt, 8))
        let folderId = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : UUID(uuidString: String(cString: sqlite3_column_text(stmt, 9)))
        let uploadId = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : UUID(uuidString: String(cString: sqlite3_column_text(stmt, 10)))
        let localUrl = sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : URL(string: String(cString: sqlite3_column_text(stmt, 11)))
        let attemptCount = Int(sqlite3_column_int(stmt, 12))
        let lastAttempt = sqlite3_column_type(stmt, 13) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 13)))
        let lastError = sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 14))

        return UploadLedgerRecord(
            id: id,
            assetLocalIdentifier: assetId,
            resourceKind: PhotoResourceKind(rawValue: kindRaw) ?? .image,
            fingerprintSuffix: suffix,
            originalFilename: originalFilename,
            uploadedFileName: uploadedFileName,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            status: UploadLedgerStatus(rawValue: statusRaw) ?? .discovered,
            backendFolderId: folderId,
            backendUploadId: uploadId,
            localStagedFileURL: localUrl,
            attemptCount: attemptCount,
            lastAttemptAt: lastAttempt,
            lastError: lastError
        )
    }


    func markExporting(id: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE upload_ledger SET status = 'exporting' WHERE id = ?;"
        try runUpdate(sql, params: [id])
    }

    func markReady(id: String, stagedFileURL: URL, sizeBytes: Int64) async throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE upload_ledger SET status = 'readyToUpload', local_staged_file_url = ?, size_bytes = ? WHERE id = ?;"
        try runUpdate(sql, params: [stagedFileURL.absoluteString, sizeBytes, id])
    }

    func markUploading(id: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE upload_ledger SET status = 'uploading' WHERE id = ?;"
        try runUpdate(sql, params: [id])
    }

    func markUploaded(id: String, backendUploadId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE upload_ledger SET status = 'uploaded', backend_upload_id = ? WHERE id = ?;"
        try runUpdate(sql, params: [backendUploadId.uuidString.lowercased(), id])
    }

    func markSyncedByUploadedFileNames(_ fileNames: Set<String>, folderId: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }
        guard !fileNames.isEmpty else { return }
        
        // SQLite transaction for bulk updates
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        
        let sql = "UPDATE upload_ledger SET status = 'synced' WHERE uploaded_file_name = ? AND backend_folder_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            try? execute("ROLLBACK;")
            throw DatabaseError.prepareFailed(errorMessage())
        }
        
        defer { sqlite3_finalize(stmt) }
        
        for fileName in fileNames {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, fileName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, folderId.uuidString.lowercased(), -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                try? execute("ROLLBACK;")
                throw DatabaseError.executionFailed(errorMessage())
            }
        }
        
        try execute("COMMIT;")
    }

    func markFailed(id: String, error: String, retryable: Bool) async throws {
        lock.lock()
        defer { lock.unlock() }
        let status = "failed"
        let attemptCountUpdate = retryable ? "attempt_count = attempt_count + 1" : "attempt_count = 99"
        let timestamp = Int64(Date().timeIntervalSince1970)
        
        let sql = "UPDATE upload_ledger SET status = '\(status)', last_error = ?, \(attemptCountUpdate), last_attempt_at = ? WHERE id = ?;"
        try runUpdate(sql, params: [error, timestamp, id])
    }

    func getLedgerCounts() async throws -> LedgerCounts {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT 
            SUM(case when status IN ('discovered', 'readyToUpload') then 1 else 0 end),
            SUM(case when status IN ('uploaded', 'synced') then 1 else 0 end),
            SUM(case when status = 'failed' then 1 else 0 end),
            SUM(case when status = 'exporting' then 1 else 0 end),
            SUM(case when status = 'uploading' then 1 else 0 end)
        FROM upload_ledger;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let queued = Int(sqlite3_column_int(stmt, 0))
            let uploaded = Int(sqlite3_column_int(stmt, 1))
            let failed = Int(sqlite3_column_int(stmt, 2))
            let exporting = Int(sqlite3_column_int(stmt, 3))
            let uploading = Int(sqlite3_column_int(stmt, 4))
            return LedgerCounts(queued: queued, uploaded: uploaded, failed: failed, exporting: exporting, uploading: uploading)
        }
        return LedgerCounts(queued: 0, uploaded: 0, failed: 0, exporting: 0, uploading: 0)
    }

    func getDashboardSummary(nextBatchLimit: Int) async throws -> LedgerDashboardSummary {
        let counts = try await getLedgerCounts()
        let remainingBytes = try await sumBytes(
            whereClause: "status IN ('discovered', 'exporting', 'readyToUpload', 'uploading', 'failed')"
        )
        let nextBatch = try await nextBatchSummary(limit: nextBatchLimit)

        return LedgerDashboardSummary(
            counts: counts,
            remainingBytes: remainingBytes,
            nextBatch: nextBatch
        )
    }

    private func sumBytes(whereClause: String) async throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT COALESCE(SUM(COALESCE(size_bytes, 0)), 0) FROM upload_ledger WHERE \(whereClause);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return sqlite3_column_int64(stmt, 0)
    }

    private func nextBatchSummary(limit: Int) async throws -> LedgerNextBatchSummary {
        let records = try await nextUploadBatch(limit: limit)
        let photoCount = records.filter { $0.resourceKind == .image }.count
        let videoCount = records.filter { $0.resourceKind == .video || $0.resourceKind == .livePhotoVideo }.count
        let totalBytes = records.reduce(Int64(0)) { partial, record in
            partial + (record.sizeBytes ?? 0)
        }

        return LedgerNextBatchSummary(
            photoCount: photoCount,
            videoCount: videoCount,
            totalBytes: totalBytes
        )
    }

    private func runUpdate(_ sql: String, params: [Any]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage())
        }
        
        defer { sqlite3_finalize(stmt) }
        
        for (index, param) in params.enumerated() {
            let bindIndex = Int32(index + 1)
            if let strVal = param as? String {
                sqlite3_bind_text(stmt, bindIndex, strVal, -1, SQLITE_TRANSIENT)
            } else if let intVal = param as? Int64 {
                sqlite3_bind_int64(stmt, bindIndex, intVal)
            } else if let intVal = param as? Int {
                sqlite3_bind_int64(stmt, bindIndex, Int64(intVal))
            } else {
                sqlite3_bind_null(stmt, bindIndex)
            }
        }
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.executionFailed(errorMessage())
        }
    }

    func clearAllRecords() async throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("DELETE FROM upload_ledger;")
    }

    private func errorMessage() -> String {
        return sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown error"
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg):
            return "Database open failed: \(msg)"
        case .prepareFailed(let msg):
            return "Database prepare failed: \(msg)"
        case .executionFailed(let msg):
            return "Database execution failed: \(msg)"
        }
    }
}

// SQLITE_TRANSIENT binding helper helper
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
