import XCTest
@testable import NexusRelayIPhone

final class TemporaryFileStoreTests: XCTestCase {
    private var store: SystemTemporaryFileStore!

    override func setUp() {
        super.setUp()
        store = SystemTemporaryFileStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testGetStagedFileURLCreatesDirectory() throws {
        let recordId = "test_record_1:image"
        let fileName = "test_image.jpg"
        
        let url = try store.getStagedFileURL(recordId: recordId, fileName: fileName)
        
        XCTAssertTrue(url.absoluteString.contains("com.nexusrelay.iphone.uploads"))
        XCTAssertTrue(url.absoluteString.contains("test_record_1_image"))
        XCTAssertEqual(url.lastPathComponent, fileName)
        
        let parentDir = url.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentDir.path))
    }

    func testDeleteStagedFile() throws {
        let recordId = "test_record_2:video"
        let fileName = "test_video.mp4"
        
        let url = try store.getStagedFileURL(recordId: recordId, fileName: fileName)
        
        // Write mock data
        let mockData = "video-data".data(using: .utf8)!
        try mockData.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        
        try store.deleteStagedFile(recordId: recordId)
        
        let parentDir = url.deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: parentDir.path))
    }
}
