import XCTest
@testable import NexusRelayIPhone

final class ChunkFileBuilderTests: XCTestCase {
    private var tempDir: URL!
    private var sourceURL: URL!
    private var builder: SystemChunkFileBuilder!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sourceURL = tempDir.appendingPathComponent("source.txt")
        
        let data = "abcdefghijklmnopqrstuvwxyz".data(using: .utf8)! // 26 bytes
        try! data.write(to: sourceURL)
        builder = SystemChunkFileBuilder()
    }

    override func tearDown() {
        builder = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSliceExactChunks() throws {
        // Slice size 10 bytes:
        // Chunk 0: abcdefghij (10 bytes)
        // Chunk 1: klmnopqrst (10 bytes)
        // Chunk 2: uvwxyz (6 bytes)
        
        let chunk0 = try builder.buildChunkFile(recordId: "record1", sourceURL: sourceURL, chunkIndex: 0, chunkSize: 10, totalSize: 26)
        let data0 = try Data(contentsOf: chunk0)
        XCTAssertEqual(String(data: data0, encoding: .utf8), "abcdefghij")
        XCTAssertEqual(data0.count, 10)
        builder.cleanChunks(recordId: "record1")

        let chunk1 = try builder.buildChunkFile(recordId: "record2", sourceURL: sourceURL, chunkIndex: 1, chunkSize: 10, totalSize: 26)
        let data1 = try Data(contentsOf: chunk1)
        XCTAssertEqual(String(data: data1, encoding: .utf8), "klmnopqrst")
        XCTAssertEqual(data1.count, 10)
        builder.cleanChunks(recordId: "record2")

        let chunk2 = try builder.buildChunkFile(recordId: "record3", sourceURL: sourceURL, chunkIndex: 2, chunkSize: 10, totalSize: 26)
        let data2 = try Data(contentsOf: chunk2)
        XCTAssertEqual(String(data: data2, encoding: .utf8), "uvwxyz")
        XCTAssertEqual(data2.count, 6)
        builder.cleanChunks(recordId: "record3")
    }

    func testInvalidOffsetThrows() {
        XCTAssertThrowsError(
            try builder.buildChunkFile(recordId: "record-error", sourceURL: sourceURL, chunkIndex: 3, chunkSize: 10, totalSize: 26)
        )
    }

    func testBuildChunkFileUsesBufferedCopyForMiddleChunk() throws {
        let fileSize = 5 * 1024 * 1024 + 123
        let chunkSize = 1 * 1024 * 1024
        let chunkIndex = 2
        let copyBufferSize = 64 * 1024

        let sourceData = Data((0..<fileSize).map { UInt8(truncatingIfNeeded: $0) })
        try sourceData.write(to: sourceURL)

        builder = SystemChunkFileBuilder(copyBufferSize: copyBufferSize)

        let chunkURL = try builder.buildChunkFile(
            recordId: "record-buffered",
            sourceURL: sourceURL,
            chunkIndex: chunkIndex,
            chunkSize: Int64(chunkSize),
            totalSize: Int64(fileSize)
        )
        defer { builder.cleanChunks(recordId: "record-buffered") }

        let chunkData = try Data(contentsOf: chunkURL)
        let expectedRangeStart = chunkIndex * chunkSize
        let expectedRangeEnd = expectedRangeStart + chunkSize
        let expectedData = sourceData.subdata(in: expectedRangeStart..<expectedRangeEnd)

        XCTAssertEqual(chunkData.count, chunkSize)
        XCTAssertEqual(chunkData, expectedData)
    }

    func testBuildChunkFileReplacesExistingChunkOutput() throws {
        let recordId = "record-replace"
        let chunkSize = 10
        let totalSize = 26

        let firstSource = "abcdefghij".data(using: .utf8)!
        try firstSource.write(to: sourceURL)
        let initialChunkURL = try builder.buildChunkFile(
            recordId: recordId,
            sourceURL: sourceURL,
            chunkIndex: 0,
            chunkSize: Int64(chunkSize),
            totalSize: Int64(totalSize)
        )
        XCTAssertEqual(try Data(contentsOf: initialChunkURL), firstSource)

        let secondSource = "uvwxyz".data(using: .utf8)!
        try secondSource.write(to: sourceURL)
        let replacedChunkURL = try builder.buildChunkFile(
            recordId: recordId,
            sourceURL: sourceURL,
            chunkIndex: 0,
            chunkSize: Int64(chunkSize),
            totalSize: Int64(secondSource.count)
        )
        defer { builder.cleanChunks(recordId: recordId) }

        let replacedData = try Data(contentsOf: replacedChunkURL)
        XCTAssertEqual(replacedData.count, secondSource.count)
        XCTAssertEqual(replacedData, secondSource)
    }
}
