import Foundation

struct UploadPolicy: Equatable {
    let streamThresholdBytes: Int64
    let chunkSizeBytes: Int64
    let maxRetries: Int
    let foregroundChunkConcurrency: Int
    let backgroundChunkConcurrency: Int

    static let nexusRelayDefault = UploadPolicy(
        streamThresholdBytes: 90 * 1024 * 1024,
        chunkSizeBytes: 30 * 1024 * 1024,
        maxRetries: 3,
        foregroundChunkConcurrency: 2,
        backgroundChunkConcurrency: 1
    )
}
