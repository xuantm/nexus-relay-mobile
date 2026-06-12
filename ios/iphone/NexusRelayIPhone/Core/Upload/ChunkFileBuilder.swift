import Foundation

protocol ChunkFileBuilder {
    func buildChunkFile(recordId: String, sourceURL: URL, chunkIndex: Int, chunkSize: Int64, totalSize: Int64) throws -> URL
    func cleanChunks(recordId: String)
}

final class SystemChunkFileBuilder: ChunkFileBuilder {
    private let tempDir: URL
    private let copyBufferSize: Int

    init(copyBufferSize: Int = UploadPolicy.nexusRelayDefault.chunkCopyBufferSize) {
        self.tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("com.nexusrelay.iphone.chunks", isDirectory: true)
        self.copyBufferSize = max(1, copyBufferSize)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    func buildChunkFile(recordId: String, sourceURL: URL, chunkIndex: Int, chunkSize: Int64, totalSize: Int64) throws -> URL {
        let offset = Int64(chunkIndex) * chunkSize
        guard offset < totalSize else {
            throw ChunkError.invalidOffset
        }
        
        let targetLength = min(chunkSize, totalSize - offset)
        
        let fileHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? fileHandle.close() }

        try fileHandle.seek(toOffset: UInt64(offset))
        let safeRecordId = recordId.replacingOccurrences(of: ":", with: "_")
        let chunkDir = tempDir.appendingPathComponent(safeRecordId, isDirectory: true)
        try FileManager.default.createDirectory(at: chunkDir, withIntermediateDirectories: true)

        let chunkURL = chunkDir.appendingPathComponent("chunk_\(chunkIndex).bin")
        try replaceChunkFile(at: chunkURL)

        let destinationHandle = try FileHandle(forWritingTo: chunkURL)
        defer { try? destinationHandle.close() }

        var remainingBytes = targetLength
        while remainingBytes > 0 {
            let bytesToRead = min(copyBufferSize, Int(remainingBytes))
            guard let data = try fileHandle.read(upToCount: bytesToRead), !data.isEmpty else {
                break
            }

            try destinationHandle.write(contentsOf: data)
            remainingBytes -= Int64(data.count)
        }

        return chunkURL
    }

    private func replaceChunkFile(at url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        if !fileManager.createFile(atPath: url.path, contents: nil) {
            throw CocoaError(.fileWriteFileExists)
        }
    }

    func cleanChunks(recordId: String) {
        let safeRecordId = recordId.replacingOccurrences(of: ":", with: "_")
        let chunkDir = tempDir.appendingPathComponent(safeRecordId, isDirectory: true)
        try? FileManager.default.removeItem(at: chunkDir)
    }
}

enum ChunkError: Error, LocalizedError {
    case invalidOffset

    var errorDescription: String? {
        switch self {
        case .invalidOffset: return "Invalid byte offset for file chunking."
        }
    }
}
