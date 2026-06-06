import UIKit
@testable import NexusRelayIPhone

final class FakeThumbnailProvider: PhotoThumbnailProvider {
    var requestedIds: [String] = []

    func thumbnail(forAssetLocalIdentifier id: String, targetSize: CGSize) async -> UIImage? {
        requestedIds.append(id)
        return UIImage(systemName: "photo")
    }
}

@MainActor
final class LibrarySyncSummaryTests: XCTestCase {
    func testSummaryComputesProgress() {
        let summary = LibrarySyncSummary(uploaded: 842, waiting: 319, failed: 3, active: 6)

        XCTAssertEqual(summary.progressPercentText, "72% uploaded")
        XCTAssertEqual(summary.summaryText, "842 uploaded · 319 waiting · 3 need attention")
        XCTAssertEqual(summary.progressFraction, 842.0 / 1170.0, accuracy: 0.001)
    }

    func testEmptySummaryDoesNotDivideByZero() {
        let summary = LibrarySyncSummary(uploaded: 0, waiting: 0, failed: 0, active: 0)

        XCTAssertEqual(summary.progressPercentText, "0% uploaded")
        XCTAssertEqual(summary.progressFraction, 0)
    }
}

