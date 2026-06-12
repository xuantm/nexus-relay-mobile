import XCTest
@testable import NexusRelayIPhone

final class UploadRoutingPolicyTests: XCTestCase {
    func testRoutesFilesUpToFiveMegabytesThroughMultipartStream() {
        let policy = UploadPolicy.nexusRelayDefault

        XCTAssertEqual(policy.route(forFileSize: 5 * 1024 * 1024), .multipartStream)
    }

    func testRoutesFilesAboveFiveAndUpToNinetyMegabytesThroughResumableStream() {
        let policy = UploadPolicy.nexusRelayDefault

        XCTAssertEqual(policy.route(forFileSize: (5 * 1024 * 1024) + 1), .resumableStream)
        XCTAssertEqual(policy.route(forFileSize: 90 * 1024 * 1024), .resumableStream)
    }

    func testRoutesFilesAboveNinetyMegabytesThroughChunkedUpload() {
        let policy = UploadPolicy.nexusRelayDefault

        XCTAssertEqual(policy.route(forFileSize: (90 * 1024 * 1024) + 1), .chunked)
    }

    func testClientChunkedUploadUsesSixteenMegabyteChunks() {
        XCTAssertEqual(UploadPolicy.nexusRelayDefault.chunkSizeBytes, 16 * 1024 * 1024)
    }

    func testQueueRouteNamesMatchDisplayNames() {
        XCTAssertEqual(UploadRoute.multipartStream.displayName, "Direct multipart upload")
        XCTAssertEqual(UploadRoute.resumableStream.displayName, "Direct resumable upload")
        XCTAssertEqual(UploadRoute.chunked.displayName, "Chunked upload")
    }
}
