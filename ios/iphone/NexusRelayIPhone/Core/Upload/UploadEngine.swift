import Foundation
import OSLog

private let uploadLogger = Logger(subsystem: "com.nexusrelay.iphone", category: "upload")

enum UploadEngineError: Error, LocalizedError {
    case missingLocalFile
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingLocalFile: return "Staged file is missing."
        case .uploadFailed(let msg): return "Upload engine error: \(msg)"
        }
    }
}

protocol UploadEngine {
    func upload(record: UploadLedgerRecord, folderId: UUID) async throws -> UUID
}

final class SystemUploadEngine: UploadEngine {
    private let apiClient: NexusRelayAPI
    private let chunkFileBuilder: ChunkFileBuilder
    private let policy: UploadPolicy
    private let progressTracker: UploadProgressTracker?

    init(
        apiClient: NexusRelayAPI,
        chunkFileBuilder: ChunkFileBuilder = SystemChunkFileBuilder(),
        policy: UploadPolicy = .nexusRelayDefault,
        progressTracker: UploadProgressTracker? = nil
    ) {
        self.apiClient = apiClient
        self.chunkFileBuilder = chunkFileBuilder
        self.policy = policy
        self.progressTracker = progressTracker
    }

    func upload(record: UploadLedgerRecord, folderId: UUID) async throws -> UUID {
        guard let localURL = record.localStagedFileURL else {
            throw UploadEngineError.missingLocalFile
        }

        let uploadStart = Date()
        let fileSize = record.sizeBytes ?? 0
        let route = policy.route(forFileSize: fileSize)
        uploadLogger.info("upload.record.started id=\(record.id, privacy: .public) route=\(route.displayName, privacy: .public) bytes=\(fileSize)")

        switch route {
        case .multipartStream, .resumableStream:
            return try await retry {
                let response = try await apiClient.streamUpload(
                    fileURL: localURL,
                    fileName: record.uploadedFileName,
                    folderId: folderId,
                    mimeType: record.mimeType,
                    fileSize: fileSize,
                    clientSyncId: record.clientSyncId.uuidString.lowercased(),
                    progress: self.progressHandler(for: record, fileSize: fileSize)
                )
                uploadLogger.info(
                    "upload.record.completed id=\(record.id, privacy: .public) route=\(route.displayName, privacy: .public) bytes=\(fileSize) elapsedMs=\(self.loggingMilliseconds(since: uploadStart))"
                )
                return response.uploadId
            }
        case .chunked:
            let uploadId = try await uploadChunked(record: record, folderId: folderId, localURL: localURL, fileSize: fileSize)
            uploadLogger.info(
                "upload.record.completed id=\(record.id, privacy: .public) route=\(route.displayName, privacy: .public) bytes=\(fileSize) elapsedMs=\(self.loggingMilliseconds(since: uploadStart))"
            )
            return uploadId
        }
    }

    private func uploadChunked(record: UploadLedgerRecord, folderId: UUID, localURL: URL, fileSize: Int64) async throws -> UUID {
        let chunkedStart = Date()
        let chunkSize = policy.chunkSizeBytes
        let totalChunks = Int(ceil(Double(fileSize) / Double(chunkSize)))
        uploadLogger.info("upload.chunked.started id=\(record.id, privacy: .public) chunks=\(totalChunks) chunkBytes=\(chunkSize)")

        defer {
            chunkFileBuilder.cleanChunks(recordId: record.id)
        }

        let initResponse = try await retry {
            try await apiClient.initUpload(
                folderId: folderId,
                fileName: record.uploadedFileName,
                totalSize: fileSize,
                totalChunks: totalChunks,
                clientSyncId: record.clientSyncId.uuidString.lowercased()
            )
        }
        let uploadId = initResponse.uploadId

        for chunkIndex in 0..<totalChunks {
            let chunkStart = Date()
            let chunkURL = try chunkFileBuilder.buildChunkFile(
                recordId: record.id,
                sourceURL: localURL,
                chunkIndex: chunkIndex,
                chunkSize: chunkSize,
                totalSize: fileSize
            )

            defer {
                if chunkURL.standardizedFileURL != localURL.standardizedFileURL {
                    try? FileManager.default.removeItem(at: chunkURL)
                }
            }

            let actualChunkSize = try getFileSize(at: chunkURL)

            try await retry {
                try await apiClient.uploadChunk(
                    uploadId: uploadId,
                    chunkIndex: chunkIndex,
                    chunkSize: actualChunkSize,
                    chunkFileURL: chunkURL,
                    progress: self.progressHandler(
                        for: record,
                        chunkIndex: chunkIndex,
                        chunkSize: chunkSize,
                        fileSize: fileSize
                    )
                )
            }
            uploadLogger.info(
                "upload.chunk.completed id=\(record.id, privacy: .public) index=\(chunkIndex) bytes=\(actualChunkSize) elapsedMs=\(self.loggingMilliseconds(since: chunkStart)) bytesPerSec=\(self.loggingBytesPerSecond(bytes: actualChunkSize, since: chunkStart))"
            )
        }

        try await retry {
            try await apiClient.completeUpload(uploadId: uploadId, fileHash: nil)
        }
        uploadLogger.info(
            "upload.chunked.completed id=\(record.id, privacy: .public) uploadId=\(uploadId.uuidString, privacy: .public) chunks=\(totalChunks) elapsedMs=\(self.loggingMilliseconds(since: chunkedStart))"
        )

        return uploadId
    }

    private func progressHandler(
        for record: UploadLedgerRecord,
        chunkIndex: Int? = nil,
        chunkSize: Int64? = nil,
        fileSize: Int64? = nil
    ) -> HTTPUploadProgressHandler? {
        guard let progressTracker else {
            return nil
        }

        return { progress in
            let offset: Int64
            if let chunkIndex = chunkIndex, let chunkSize = chunkSize {
                offset = Int64(chunkIndex) * chunkSize
            } else {
                offset = 0
            }
            
            let actualBytesSent = offset + progress.bytesSent
            let actualTotalBytes: Int64
            if chunkIndex != nil {
                actualTotalBytes = fileSize ?? record.sizeBytes ?? progress.totalBytes ?? progress.bytesSent
            } else {
                actualTotalBytes = progress.totalBytes ?? fileSize ?? record.sizeBytes ?? progress.bytesSent
            }
            
            await progressTracker.recordUploadProgress(
                recordId: record.id,
                bytesSent: actualBytesSent,
                totalBytes: actualTotalBytes
            )
        }
    }

    private func retry<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error = NSError(domain: "UploadEngine", code: -1)
        var delaySeconds = 1.0
        
        for attempt in 1...policy.maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if isPermanentFailure(error) {
                    throw error
                }
                if attempt < policy.maxRetries {
                    // Exponential backoff sleep
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    delaySeconds *= 2.0
                }
            }
        }
        throw lastError
    }

    private func isPermanentFailure(_ error: Error) -> Bool {
        if let apiErr = error as? APIError {
            switch apiErr {
            case .requestFailed(let statusCode, _):
                return statusCode >= 400 && statusCode < 500 && statusCode != 401
            default:
                return false
            }
        }
        return false
    }

    private func getFileSize(at url: URL) throws -> Int64 {
        let path = url.path
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        if let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return attrs[.size] as? Int64 ?? 0
    }

    private func loggingMilliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private func loggingBytesPerSecond(bytes: Int64, since start: Date) -> Int64 {
        let elapsed = max(Date().timeIntervalSince(start), 0.001)
        return Int64((Double(bytes) / elapsed).rounded())
    }
}
