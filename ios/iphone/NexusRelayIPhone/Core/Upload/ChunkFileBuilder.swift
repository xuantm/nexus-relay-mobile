import Foundation

protocol ChunkFileBuilder {
    func buildChunkFile(recordId: String, sourceURL: URL, chunkIndex: Int, chunkSize: Int64, totalSize: Int64) throws -> URL
    func cleanChunks(recordId: String)
}

final class SystemChunkFileBuilder: ChunkFileBuilder {
    private let tempDir: URL

    init() {
        self.tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("com.nexusrelay.iphone.chunks", isDirectory: true)
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
        let data = try fileHandle.read(upToCount: Int(targetLength)) ?? Data()
        
        let safeRecordId = recordId.replacingOccurrences(of: ":", with: "_")
        let chunkDir = tempDir.appendingPathComponent(safeRecordId, isDirectory: true)
        try FileManager.default.createDirectory(at: chunkDir, withIntermediateDirectories: true)
        
        let chunkURL = chunkDir.appendingPathComponent("chunk_\(chunkIndex).bin")
        try data.write(to: chunkURL)
        
        return chunkURL
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
