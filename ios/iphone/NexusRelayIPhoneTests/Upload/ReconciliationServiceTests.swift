import XCTest
@testable import NexusRelayIPhone

final class MockPhotoLibraryClient: PhotoLibraryClient {
    var candidates: [PhotoAssetCandidate] = []
    func authorizationStatus() -> PhotoLibraryAuthorizationStatus {
        return .authorized
    }
    func requestAuthorization() async -> PhotoLibraryAuthorizationStatus {
        return .authorized
    }
    func fetchCandidates(includeVideos: Bool, includeLivePhotoVideo: Bool) async throws -> [PhotoAssetCandidate] {
        return candidates
    }
}

final class MockNexusRelayReconciliationAPI: NexusRelayAPI {
    var mediaItems: [MediaItemDTO] = []
    
    func login(username: String, password: String) async throws -> AuthSession { fatalError() }
    func currentUser() async throws -> BrowserAuthResponse { fatalError() }
    func listRootFolders() async throws -> [FolderDTO] { fatalError() }
    func createFolder(name: String, parentId: UUID?) async throws -> FolderDTO { fatalError() }
    
    func listFolderMedia(folderId: UUID, pageSize: Int, cursor: String?) async throws -> FolderContentDTO {
        let folder = FolderDTO(id: folderId, name: "iPhone Uploads", parentId: nil, googleDriveFolderId: nil, createdAt: Date(), childCount: 0, mediaCount: 0)
        let page = CursorPageDTO(items: mediaItems, pageSize: pageSize, hasMore: false, nextCursor: nil)
        let folderPage = OffsetPageDTO(items: [], page: 1, pageSize: pageSize, hasMore: false, nextPage: nil)
        
        return FolderContentDTO(
            folder: folder,
            subFolders: [],
            mediaItems: mediaItems,
            breadcrumbs: [],
            page: 1,
            pageSize: pageSize,
            hasMore: false,
            nextPage: nil,
            media: page,
            folders: folderPage
        )
    }
    
    func streamUpload(fileURL: URL, fileName: String, folderId: UUID, mimeType: String, fileSize: Int64) async throws -> StreamUploadResponse { fatalError() }
    func initUpload(folderId: UUID, fileName: String, totalSize: Int64, totalChunks: Int) async throws -> InitUploadResponse { fatalError() }
    func uploadChunk(uploadId: UUID, chunkIndex: Int, chunkSize: Int64, chunkFileURL: URL) async throws { fatalError() }
    func completeUpload(uploadId: UUID, fileHash: String?) async throws { fatalError() }
}

final class ReconciliationServiceTests: XCTestCase {
    private var tempDir: URL!
    private var dbURL: URL!
    private var ledger: SQLiteUploadLedger!
    private var scanner: MockPhotoLibraryClient!
    private var api: MockNexusRelayReconciliationAPI!
    private var service: ReconciliationService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("ledger.sqlite")
        ledger = try! SQLiteUploadLedger(dbURL: dbURL)
        scanner = MockPhotoLibraryClient()
        api = MockNexusRelayReconciliationAPI()
        service = ReconciliationService(apiClient: api, photosScanner: scanner, ledger: ledger)
    }

    override func tearDown() {
        ledger = nil
        service = nil
        scanner = nil
        api = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testExtractSuffix() {
        XCTAssertEqual(service.extractSuffix(from: "photo__nr-bd02941f22ac9170.jpg"), "bd02941f22ac9170")
        XCTAssertEqual(service.extractSuffix(from: "photo__nr-BD02941F22AC9170.PNG"), "bd02941f22ac9170")
        XCTAssertNil(service.extractSuffix(from: "photo.jpg"))
        XCTAssertNil(service.extractSuffix(from: "photo__nr-short.jpg"))
        XCTAssertNil(service.extractSuffix(from: "photo__nr-nonhex123456789g.jpg"))
    }

    func testReconciliationMarksSynced() async throws {
        let folderId = UUID()
        let date = Date()
        
        let candidate1 = PhotoAssetCandidate(
            assetLocalIdentifier: "asset1",
            resourceKind: .image,
            originalFilename: "photo1.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: date,
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 1024
        )
        
        let candidate2 = PhotoAssetCandidate(
            assetLocalIdentifier: "asset2",
            resourceKind: .image,
            originalFilename: "photo2.jpg",
            uniformTypeIdentifier: "public.jpeg",
            mimeType: "image/jpeg",
            creationDate: date,
            modificationDate: nil,
            pixelWidth: 800,
            pixelHeight: 600,
            durationSeconds: nil,
            resourceFileSize: 1024
        )
        
        scanner.candidates = [candidate1, candidate2]
        
        // Suffix of candidate1:
        let fp1 = AssetFingerprinter.generateFingerprint(candidate: candidate1)
        let suffix1 = AssetFingerprinter.getFingerprintSuffix(fingerprint: fp1)
        
        let mockRemoteMedia = MediaItemDTO(
            id: UUID(),
            folderId: folderId,
            fileName: "photo1__nr-\(suffix1).jpg",
            size: 1024,
            mimeType: "image/jpeg",
            width: 800,
            height: 600,
            status: .completed,
            mediaType: .image,
            durationSeconds: nil,
            thumbnailGenerated: true,
            videoCodec: nil,
            createdAt: date,
            completedAt: date
        )
        
        api.mediaItems = [mockRemoteMedia]
        
        // Reconcile
        try await service.reconcile(folderId: folderId)
        
        // Verify ledger status
        let batch = try await ledger.nextUploadBatch(limit: 10)
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch.first?.assetLocalIdentifier, "asset2") // asset1 was matched and markedSynced, so it's not in the queue!
    }

    func testDatabaseCorruptionRecovery() {
        // Write corrupt garbage data into the database file
        let badData = "corrupted-file-data".data(using: .utf8)!
        try! badData.write(to: dbURL)
        
        var isCorrupted = false
        let recoveredLedger = LedgerFactory.createOrRecoverLedger(dbURL: dbURL, isCorrupted: &isCorrupted)
        
        XCTAssertTrue(isCorrupted)
        XCTAssertNotNil(recoveredLedger)
        
        // Verify backup corrupt database exists
        let urls = try! FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertTrue(urls.contains { $0.lastPathComponent.contains("UploadLedger.corrupt.") })
    }
}
