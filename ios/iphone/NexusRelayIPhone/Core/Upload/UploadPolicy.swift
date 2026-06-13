import Foundation

struct UploadPolicy: Equatable {
    let multipartStreamMaxBytes: Int64
    let directStreamMaxBytes: Int64
    let chunkSizeBytes: Int64
    let maxRetries: Int
    let foregroundChunkConcurrency: Int
    let backgroundChunkConcurrency: Int
    let recordUploadConcurrency: Int
    let progressThrottleMilliseconds: Int
    let chunkCopyBufferSize: Int

    static let nexusRelayDefault = UploadPolicy(
        multipartStreamMaxBytes: 5 * 1024 * 1024,
        directStreamMaxBytes: 20 * 1024 * 1024,
        chunkSizeBytes: 16 * 1024 * 1024,
        maxRetries: 3,
        foregroundChunkConcurrency: 2,
        backgroundChunkConcurrency: 1,
        recordUploadConcurrency: 6,
        progressThrottleMilliseconds: 300,
        chunkCopyBufferSize: 1024 * 1024
    )

    func route(forFileSize fileSize: Int64) -> UploadRoute {
        if fileSize > directStreamMaxBytes {
            return .chunked
        }

        return fileSize <= multipartStreamMaxBytes ? .multipartStream : .resumableStream
    }

    var streamThresholdBytes: Int64 {
        directStreamMaxBytes
    }
}
