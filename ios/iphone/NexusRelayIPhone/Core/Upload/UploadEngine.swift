import Foundation

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

    init(
        apiClient: NexusRelayAPI,
        chunkFileBuilder: ChunkFileBuilder = SystemChunkFileBuilder(),
        policy: UploadPolicy = .nexusRelayDefault
    ) {
        self.apiClient = apiClient
        self.chunkFileBuilder = chunkFileBuilder
        self.policy = policy
    }

    func upload(record: UploadLedgerRecord, folderId: UUID) async throws -> UUID {
        guard let localURL = record.localStagedFileURL else {
            throw UploadEngineError.missingLocalFile
        }
        
        let fileSize = record.sizeBytes ?? 0
        
        if fileSize <= policy.streamThresholdBytes {
            return try await retry {
                let response = try await apiClient.streamUpload(
                    fileURL: localURL,
                    fileName: record.uploadedFileName,
                    folderId: folderId,
                    mimeType: record.mimeType,
                    fileSize: fileSize
                )
                return response.uploadId
            }
        } else {
            // Chunked upload
            let chunkSize = policy.chunkSizeBytes
            let totalChunks = Int(ceil(Double(fileSize) / Double(chunkSize)))
            
            defer {
                chunkFileBuilder.cleanChunks(recordId: record.id)
            }
            
            // 1. Initialize
            let initResponse = try await retry {
                try await apiClient.initUpload(
                    folderId: folderId,
                    fileName: record.uploadedFileName,
                    totalSize: fileSize,
                    totalChunks: totalChunks
                )
            }
            let uploadId = initResponse.uploadId
            
            // 2. Upload chunks
            for chunkIndex in 0..<totalChunks {
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
                        chunkFileURL: chunkURL
                    )
                }
            }
            
            // 3. Complete
            try await retry {
                try await apiClient.completeUpload(uploadId: uploadId, fileHash: nil)
            }
            
            return uploadId
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
}
