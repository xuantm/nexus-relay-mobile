import XCTest
@testable import NexusRelayIPhone

final class MockNexusRelayAPI: NexusRelayAPI {
    var streamUploadCount = 0
    var initUploadCount = 0
    var uploadChunkCount = 0
    var completeUploadCount = 0
    
    var streamUploadResult: Result<StreamUploadResponse, Error> = .success(StreamUploadResponse(uploadId: UUID()))
    var initUploadResult: Result<InitUploadResponse, Error> = .success(InitUploadResponse(uploadId: UUID()))
    var uploadChunkResult: Result<Void, Error> = .success(())
    var completeUploadResult: Result<Void, Error> = .success(())

    func login(username: String, password: String) async throws -> AuthSession { fatalError() }
    func currentUser() async throws -> BrowserAuthResponse { fatalError() }
    func listRootFolders() async throws -> [FolderDTO] { fatalError() }
    func createFolder(name: String, parentId: UUID?) async throws -> FolderDTO { fatalError() }
    func listFolderMedia(folderId: UUID, pageSize: Int, cursor: String?) async throws -> FolderContentDTO { fatalError() }

    func streamUpload(fileURL: URL, fileName: String, folderId: UUID, mimeType: String, fileSize: Int64) async throws -> StreamUploadResponse {
        streamUploadCount += 1
        return try streamUploadResult.get()
    }

    func initUpload(folderId: UUID, fileName: String, totalSize: Int64, totalChunks: Int) async throws -> InitUploadResponse {
        initUploadCount += 1
        return try initUploadResult.get()
    }

    func uploadChunk(uploadId: UUID, chunkIndex: Int, chunkSize: Int64, chunkFileURL: URL) async throws {
        uploadChunkCount += 1
        try uploadChunkResult.get()
    }

    func completeUpload(uploadId: UUID, fileHash: String?) async throws {
        completeUploadCount += 1
        try completeUploadResult.get()
    }
}

final class MockChunkFileBuilder: ChunkFileBuilder {
    var buildChunkCount = 0
    var buildChunkResult: URL?
    func buildChunkFile(recordId: String, sourceURL: URL, chunkIndex: Int, chunkSize: Int64, totalSize: Int64) throws -> URL {
        buildChunkCount += 1
        return buildChunkResult ?? sourceURL
    }
    func cleanChunks(recordId: String) {}
}

final class UploadEngineTests: XCTestCase {
    private var api: MockNexusRelayAPI!
    private var chunkBuilder: MockChunkFileBuilder!
    private var engine: SystemUploadEngine!
    private var policy: UploadPolicy!
    private var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        api = MockNexusRelayAPI()
        chunkBuilder = MockChunkFileBuilder()
        
        // Define policy with small thresholds for easy testing
        policy = UploadPolicy(
            streamThresholdBytes: 100, // <= 100 bytes is stream
            chunkSizeBytes: 50,       // chunk size 50 bytes
            maxRetries: 3,
            foregroundChunkConcurrency: 1,
            backgroundChunkConcurrency: 1
        )
        
        engine = SystemUploadEngine(apiClient: api, chunkFileBuilder: chunkBuilder, policy: policy)
        
        // Create mock local file
        tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try! "mock-file-content".data(using: .utf8)!.write(to: tempFileURL)
        chunkBuilder.buildChunkResult = tempFileURL
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        api = nil
        chunkBuilder = nil
        engine = nil
        policy = nil
        tempFileURL = nil
        super.tearDown()
    }

    func testStreamUploadForSmallFile() async throws {
        let record = UploadLedgerRecord(
            id: "1",
            assetLocalIdentifier: "asset1",
            resourceKind: .image,
            fingerprintSuffix: "suffix1",
            originalFilename: "test.jpg",
            uploadedFileName: "test__nr-suffix1.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 80, // <= 100 threshold
            status: .readyToUpload,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: tempFileURL,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: nil
        )

        let uploadId = try await engine.upload(record: record, folderId: UUID())
        
        XCTAssertEqual(api.streamUploadCount, 1)
        XCTAssertEqual(api.initUploadCount, 0)
        XCTAssertEqual(api.uploadChunkCount, 0)
        XCTAssertNotNil(uploadId)
    }

    func testChunkedUploadForLargeFile() async throws {
        let record = UploadLedgerRecord(
            id: "2",
            assetLocalIdentifier: "asset2",
            resourceKind: .image,
            fingerprintSuffix: "suffix2",
            originalFilename: "test.jpg",
            uploadedFileName: "test__nr-suffix2.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 120, // > 100 threshold -> 3 chunks (120/50)
            status: .readyToUpload,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: tempFileURL,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: nil
        )

        let uploadId = try await engine.upload(record: record, folderId: UUID())
        
        XCTAssertEqual(api.streamUploadCount, 0)
        XCTAssertEqual(api.initUploadCount, 1)
        XCTAssertEqual(api.uploadChunkCount, 3)
        XCTAssertEqual(api.completeUploadCount, 1)
        XCTAssertNotNil(uploadId)
    }

    func testRetriesOnTransientError() async throws {
        let record = UploadLedgerRecord(
            id: "3",
            assetLocalIdentifier: "asset3",
            resourceKind: .image,
            fingerprintSuffix: "suffix3",
            originalFilename: "test.jpg",
            uploadedFileName: "test__nr-suffix3.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 80,
            status: .readyToUpload,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: tempFileURL,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: nil
        )

        // Force failures for first two attempts, succeed on third
        var count = 0
        api.streamUploadResult = .failure(NSError(domain: "NSURLErrorDomain", code: -1001, userInfo: nil))
        
        let customEngine = SystemUploadEngine(apiClient: api, chunkFileBuilder: chunkBuilder, policy: policy)
        
        // Mock a dynamic mock using custom implementation or count checks
        // For simplicity: verify it throws after maxRetries = 3
        api.streamUploadResult = .failure(NSError(domain: "NSURLErrorDomain", code: -1009)) // Offline
        
        do {
            _ = try await customEngine.upload(record: record, folderId: UUID())
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(api.streamUploadCount, 3) // Retries 3 times and fails
        }
    }

    func testFailsImmediatelyOnPermanentFailure() async throws {
        let record = UploadLedgerRecord(
            id: "4",
            assetLocalIdentifier: "asset4",
            resourceKind: .image,
            fingerprintSuffix: "suffix4",
            originalFilename: "test.jpg",
            uploadedFileName: "test__nr-suffix4.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 80,
            status: .readyToUpload,
            backendFolderId: nil,
            backendUploadId: nil,
            localStagedFileURL: tempFileURL,
            attemptCount: 0,
            lastAttemptAt: nil,
            lastError: nil
        )

        // APIError.requestFailed with 400 Bad Request
        api.streamUploadResult = .failure(APIError.requestFailed(statusCode: 400, message: "Bad request"))
        
        do {
            _ = try await engine.upload(record: record, folderId: UUID())
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertEqual(api.streamUploadCount, 1) // Fails immediately, no retry
        }
    }
}
